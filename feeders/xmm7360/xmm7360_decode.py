"""Parse XMM7360 AT measurement responses into signal metrics.

Source commands (on the modem's command port, /dev/wwan0at1):
  AT+XCESQ?  -> +XCESQ: <mode>,<rxlev>,<ber>,<rscp>,<ecno>,<rsrq>,<rsrp>,<sinr>
                rsrq index 0-34 (255 unknown), rsrp index 0-97 (255 unknown),
                sinr in half-dB steps (255 unknown). 3GPP TS 27.007 mappings,
                bin lower bounds (rsrq: 0.5*idx - 20; rsrp: idx - 141).
  AT+XMCI=1  -> +XMCI: <type>,<mcc>,<mnc>,<tac>,<ci>,<pci>,<dl_earfcn>,<ul_earfcn>,...
                type 4 = serving LTE cell, type 5 = neighbour; dl_earfcn is a
                quoted hex field, and the quoted hex after the measurement trio
                is Timing-Advance (0x7FFFFFFF/absent on neighbours and idle).
  AT+GTCAINFO? -> leading component-carrier count, then one line per carrier
                (band + dl/ul bandwidth code); carrier aggregation summary.
  AT+CSCON?  -> +CSCON: <n>,<mode>  RRC connection state (1 connected, 0 idle).
  AT+COPS?   -> +COPS: <mode>,<format>,"<operator>"  registered operator name.

History note: this project first decoded the RPC channel's radio-signal
indication. Hardware correlation (2026-07-18) proved those fields were the
serving cell's IDENTITY (cell-id/PCI packed words) — constants that merely
looked like plausible RF values — while these AT queries return the actual
live measurements. The privacy rule stands: parse only measurements; never
return TAC/cell-id/PCI.
"""
import os
import re
import sys

# The EARFCN band table, band_for_earfcn, freq_mhz_for_earfcn and quality_pct
# are shared across feeders; import them from the shared module installed
# alongside this file. Re-exported here so existing callers keep importing them
# from xmm7360_decode unchanged.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [_SCRIPT_DIR, os.path.join(_SCRIPT_DIR, '..', 'shared')]
from cellsignal_bands import (  # noqa: E402,F401
    BAND_RANGES,
    band_for_earfcn,
    freq_mhz_for_earfcn,
    quality_pct,
)

_XCESQ_RE = re.compile(
    r'\+XCESQ:\s*\d+,\s*\d+,\s*\d+,\s*\d+,\s*\d+,\s*(\d+),\s*(\d+),\s*(-?\d+)')
_XMCI_RE = re.compile(r'\+XMCI:\s*([0-9]+),(.*)')
_GTCAINFO_RE = re.compile(r'\+GTCAINFO:\s*(.*)')
_CSCON_RE = re.compile(r'\+CSCON:\s*(\d+)(?:\s*,\s*(\d+))?')
_COPS_RE = re.compile(r'\+COPS:\s*\d+\s*,\s*([012])\s*,\s*"([^"]*)"')

# 3GPP dl_bw code -> channel bandwidth in MHz (GTCAINFO / TS 36.101).
BANDWIDTH_MHZ = {0: 1.4, 1: 3, 2: 5, 3: 10, 4: 15, 5: 20}

# Timing-Advance N/A sentinel (neighbour lines and idle report this).
_TA_NA = 0x7FFFFFFF
_METERS_PER_TA = 78.125          # one-way LTE Ts distance step (≈ c * 16 * Ts / 2)


def parse_xcesq(text):
    """Extract {rsrp_dbm, rsrq_db, snr_db} from an AT+XCESQ? response.
    Unknown markers (255) and unparseable input yield None values."""
    out = {'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None}
    m = _XCESQ_RE.search(text or '')
    if not m:
        return out
    rsrq_i, rsrp_i, sinr = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if rsrp_i != 255 and 0 <= rsrp_i <= 97:
        out['rsrp_dbm'] = float(rsrp_i - 141)
    if rsrq_i != 255 and 0 <= rsrq_i <= 34:
        out['rsrq_db'] = rsrq_i * 0.5 - 20.0   # TS 27.007 bin lower bound, like rsrp
    if sinr != 255:
        out['snr_db'] = sinr / 2.0
    return out


def _decode_xmci_line(rest):
    """Decode one XMCI line body into {earfcn, rsrp_dbm, rsrq_db, snr_db,
    timing_advance}. Serving and neighbour lines share this field layout; the
    caller decides which fields to keep. Identifier fields (tac/ci/pci) are
    read past and never returned."""
    m = {'earfcn': None, 'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None,
         'timing_advance': None}
    # dl_earfcn is the 4th quoted hex field (tac, ci, pci, dl, ul, ...).
    quoted = re.findall(r'"0x([0-9A-Fa-f]+)"', rest)
    if len(quoted) >= 4:
        try:
            earfcn = int(quoted[3], 16)
            if 0 < earfcn < 70000:
                m['earfcn'] = earfcn
        except ValueError:
            pass
    # The measurement trio: three bare integers, immediately followed by the
    # quoted-hex Timing-Advance field (0x7FFFFFFF/absent -> N/A, 0 -> idle).
    trio = re.search(r'",\s*(\d+),\s*(\d+),\s*(-?\d+)\s*,\s*"0x([0-9A-Fa-f]+)"', rest)
    if trio:
        rsrp_i, rsrq_i, sinr = (int(trio.group(1)), int(trio.group(2)),
                                int(trio.group(3)))
        if 0 <= rsrp_i <= 97:
            m['rsrp_dbm'] = float(rsrp_i - 141)
        if 0 <= rsrq_i <= 34:
            m['rsrq_db'] = rsrq_i * 0.5 - 20.0
        if sinr != 255:
            m['snr_db'] = sinr / 2.0
        try:
            ta = int(trio.group(4), 16)
            if 0 < ta != _TA_NA:
                m['timing_advance'] = ta
        except ValueError:
            pass
    return m


def parse_xmci(text):
    """Extract the serving LTE cell and detected neighbours from an AT+XMCI
    response. Type-4 lines are the serving cell (live trio + EARFCN + valid
    Timing-Advance); type-5 lines are neighbours (band/EARFCN/RSRP/RSRQ; their
    TA field reads 0x7FFFFFFF N/A). Empirically (45-sample correlation,
    2026-07-18) the serving trio moves per sample while AT+XCESQ?'s report can
    stay frozen for hours. Same index mappings as XCESQ. Identifier fields
    (tac/ci/pci) are never returned; neighbour lists are ordered as received."""
    out = {'earfcn': None, 'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None,
           'timing_advance': None, 'neighbors': []}
    serving_seen = False
    for line_m in _XMCI_RE.finditer(text or ''):
        line_type = line_m.group(1)
        if line_type not in ('4', '5'):
            continue
        m = _decode_xmci_line(line_m.group(2))
        if line_type == '4':
            if not serving_seen:
                serving_seen = True
                out['earfcn'] = m['earfcn']
                out['rsrp_dbm'] = m['rsrp_dbm']
                out['rsrq_db'] = m['rsrq_db']
                out['snr_db'] = m['snr_db']
                out['timing_advance'] = m['timing_advance']
        elif m['earfcn'] is not None:
            out['neighbors'].append({
                'band': band_for_earfcn(m['earfcn']),
                'earfcn': m['earfcn'],
                'rsrp_dbm': m['rsrp_dbm'],
                'rsrq_db': m['rsrq_db'],
            })
    return out


def parse_gtcainfo(text):
    """Decode AT+GTCAINFO? -> {carriers, bands, aggregate_mhz,
    serving_bandwidth_mhz}. The leading line is the component-carrier count;
    each following line is one carrier. The PCell line carries mcc/mnc/tac/cid,
    the SCell line omits them, so band is read from the front (2nd field) and
    dl_bw from the back (2nd-to-last field) to stay robust to that difference.
    `serving_bandwidth_mhz` is the first (PCell) carrier's downlink bandwidth;
    `aggregate_mhz` sums every carrier's downlink bandwidth. Identifier fields
    (tac/cid) are read past and never returned."""
    out = {'carriers': None, 'bands': [], 'aggregate_mhz': None,
           'serving_bandwidth_mhz': None}
    carrier_rows = []
    for line_m in _GTCAINFO_RE.finditer(text or ''):
        fields = [f.strip() for f in line_m.group(1).split(',')]
        if len(fields) == 1:
            if out['carriers'] is None and fields[0].isdigit():
                out['carriers'] = int(fields[0])
        elif len(fields) >= 4:
            carrier_rows.append(fields)
    if not carrier_rows:
        return out
    if out['carriers'] is None:
        out['carriers'] = len(carrier_rows)
    total = 0.0
    have_bw = False
    for i, fields in enumerate(carrier_rows):
        band = _band_label(fields[1])
        if band:
            out['bands'].append(band)
        bw = BANDWIDTH_MHZ.get(_to_int(fields[-2]))
        if bw is None:
            continue
        total += bw
        have_bw = True
        if i == 0:
            out['serving_bandwidth_mhz'] = bw
    if have_bw:
        out['aggregate_mhz'] = int(total) if total == int(total) else total
    return out


def parse_cscon(text):
    """Decode AT+CSCON? RRC connection state -> 'connected'|'idle'|None.
    Read form is `+CSCON: <n>,<mode>`; <mode> 1=connected, 0=idle."""
    m = _CSCON_RE.search(text or '')
    if not m:
        return None
    mode = m.group(2) if m.group(2) is not None else m.group(1)
    if mode == '1':
        return 'connected'
    if mode == '0':
        return 'idle'
    return None


def parse_cops_operator(text):
    """Decode AT+COPS? -> operator name string, or None. Only the alphanumeric
    formats (0 long, 1 short) yield a name; numeric format (2) is a PLMN code,
    not a name, so it returns None."""
    m = _COPS_RE.search(text or '')
    if not m:
        return None
    fmt, name = m.group(1), m.group(2).strip()
    if fmt == '2':
        return None
    return name or None


def distance_m(ta):
    """Line-of-sight distance to the serving tower from Timing-Advance, metres.
    None when TA is absent or 0 (idle). Granularity ≈ 78 m; radio path, not
    road distance."""
    if ta is None or ta <= 0:
        return None
    return round(ta * _METERS_PER_TA)


def _band_label(value):
    """Normalise a GTCAINFO band field ('12' or 'B12') to a 'B12' label."""
    value = (value or '').strip()
    if not value:
        return None
    if value[0] in 'Bb':
        return 'B' + value[1:]
    if value.isdigit():
        return 'B' + value
    return None


def _to_int(value):
    try:
        return int((value or '').strip())
    except ValueError:
        return None
