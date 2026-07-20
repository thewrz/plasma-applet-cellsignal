"""Decode ModemManager ``mmcli --output-json`` documents into signal metrics.

Consumes the JSON emitted by:
  mmcli -L -J                     -> {"modem-list": ["/org/.../Modem/0", ...]}
  mmcli -m <i> -J                 -> {"modem": {"generic": {...}, "3gpp": {...}}}
  mmcli -m <i> --signal-get -J    -> {"modem": {"signal": {"lte": {...}, "5g": {...}}}}
  mmcli -m <i> --get-cell-info -J -> {"modem": {"cell-info": [ {...}, ... ]}}

ModemManager already reports signal metrics in dBm/dB (no 3GPP index mapping),
so values pass through as floats. mmcli renders unknown values and empty fields
as the string ``"--"``; every numeric field is parsed leniently and becomes
``None`` when unknown or unparseable.

Privacy: GetCellInfo carries cell identifiers (``tac``, ``ci``, ``physical-ci``).
This decoder reads only the EARFCN and RF measurements from each cell; the
identifier fields are never read into the result. See docs/CONTRACT.md.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cellsignal_bands import band_for_earfcn  # noqa: E402

# mmcli access-technology token -> (contract tech, signal-dict key), best first.
# The first token present in a modem's access-technologies list wins.
_TECH_TABLE = [
    ('5gnr', 'nr5g', '5g'),
    ('lte', 'lte', 'lte'),
    ('hspa-plus', 'umts', 'umts'),
    ('hspa', 'umts', 'umts'),
    ('hsupa', 'umts', 'umts'),
    ('hsdpa', 'umts', 'umts'),
    ('umts', 'umts', 'umts'),
    ('edge', 'gsm', 'gsm'),
    ('gprs', 'gsm', 'gsm'),
    ('gsm', 'gsm', 'gsm'),
]

# contract tech -> signal sub-dict key, for reading the per-technology metrics.
_SIGNAL_KEY = {'nr5g': '5g', 'lte': 'lte', 'umts': 'umts', 'gsm': 'gsm'}

# Fallback scan order when the active tech's dict carries no usable RSRP.
_SIGNAL_SCAN = ['lte', '5g', 'umts', 'gsm']


def _num(value):
    """Parse an mmcli numeric field to float; '--'/''/None/garbage -> None."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if not text or text == '--':
        return None
    try:
        return float(text)
    except ValueError:
        return None


def _int(value):
    """Parse an mmcli integer field; '--'/''/None/garbage -> None."""
    n = _num(value)
    return int(n) if n is not None else None


def modem_indexes(list_doc):
    """Return the integer modem indexes from a ``mmcli -L -J`` document.

    Each entry is a D-Bus path like ``/org/.../Modem/0``; the trailing integer
    is the index mmcli accepts as ``-m <i>``. Unparseable entries are skipped;
    an absent or empty list yields ``[]`` (the no-modem case).
    """
    out = []
    for path in (list_doc or {}).get('modem-list') or []:
        tail = str(path).rstrip('/').rsplit('/', 1)[-1]
        if tail.isdigit():
            out.append(int(tail))
    return out


def best_tech(access_technologies):
    """Return ``(contract_tech, signal_key)`` for a list of mmcli access-tech
    tokens, choosing the highest-generation one present, or ``(None, None)``."""
    tokens = {str(t).strip().lower() for t in (access_technologies or [])}
    for token, tech, key in _TECH_TABLE:
        if token in tokens:
            return tech, key
    return None, None


def parse_modem_info(info_doc):
    """Extract ``{state, tech, operator}`` from a ``mmcli -m <i> -J`` document.

    ``state`` is ModemManager's own state string (e.g. ``connected``,
    ``registered``, ``disabled``); the feeder maps it to a contract state.
    ``tech`` is the contract technology label for the current access tech.
    ``operator`` is the registered network name, or ``None`` when absent.
    """
    modem = (info_doc or {}).get('modem') or {}
    generic = modem.get('generic') or {}
    threegpp = modem.get('3gpp') or {}

    state = generic.get('state')
    state = state.strip() if isinstance(state, str) and state.strip() not in ('', '--') else state
    if not isinstance(state, str) or state in ('', '--'):
        state = None

    tech, _key = best_tech(generic.get('access-technologies'))

    operator = threegpp.get('operator-name')
    if not isinstance(operator, str) or operator.strip() in ('', '--'):
        operator = None
    else:
        operator = operator.strip()

    return {'state': state, 'tech': tech, 'operator': operator}


def _read_signal_dict(signal, key):
    d = signal.get(key) or {}
    return {
        'rsrp_dbm': _num(d.get('rsrp')),
        'rsrq_db': _num(d.get('rsrq')),
        'snr_db': _num(d.get('snr')),
        'rssi_dbm': _num(d.get('rssi')),   # absent on 5g -> None
    }


def parse_signal(signal_doc, tech):
    """Extract ``{rsrp_dbm, rsrq_db, snr_db, rssi_dbm}`` from ``--signal-get``.

    Reads the sub-dict for ``tech`` first; if that dict has no RSRP (modem not
    yet polled on that tech, or tech unknown) it scans the other technology
    dicts for the first one carrying a usable RSRP. All-unknown yields all None.
    """
    signal = (signal_doc or {}).get('modem', {}).get('signal') or {}
    key = _SIGNAL_KEY.get(tech)
    if key is not None:
        out = _read_signal_dict(signal, key)
        if out['rsrp_dbm'] is not None:
            return out
    for scan_key in _SIGNAL_SCAN:
        out = _read_signal_dict(signal, scan_key)
        if out['rsrp_dbm'] is not None:
            return out
    # Nothing had an RSRP; still surface the active tech's other fields if any.
    return _read_signal_dict(signal, key) if key is not None else {
        'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None, 'rssi_dbm': None,
    }


def parse_cell_info(cell_doc):
    """Extract ``{earfcn, neighbors}`` from a ``--get-cell-info`` document.

    The serving LTE cell (``serving == "yes"``) supplies the downlink EARFCN
    used to derive band and frequency. Every other LTE cell that reports an
    EARFCN becomes a neighbour record ``{band, earfcn, rsrp_dbm, rsrq_db}``.
    Identifier fields (``tac``/``ci``/``physical-ci``) are never read. A modem
    or ModemManager without cell-info support yields ``{earfcn: None,
    neighbors: []}``.
    """
    out = {'earfcn': None, 'neighbors': []}
    for cell in (cell_doc or {}).get('modem', {}).get('cell-info') or []:
        if not isinstance(cell, dict):
            continue
        if str(cell.get('cell-type', '')).strip().lower() != 'lte':
            continue
        earfcn = _int(cell.get('earfcn'))
        if earfcn is None:
            continue
        serving = str(cell.get('serving', '')).strip().lower() == 'yes'
        if serving:
            if out['earfcn'] is None:
                out['earfcn'] = earfcn
            continue
        out['neighbors'].append({
            'band': band_for_earfcn(earfcn),
            'earfcn': earfcn,
            'rsrp_dbm': _num(cell.get('rsrp')),
            'rsrq_db': _num(cell.get('rsrq')),
        })
    return out
