"""Parse XMM7360 AT measurement responses into signal metrics.

Source commands (on the modem's command port, /dev/wwan0at1):
  AT+XCESQ?  -> +XCESQ: <mode>,<rxlev>,<ber>,<rscp>,<ecno>,<rsrq>,<rsrp>,<sinr>
                rsrq index 0-34 (255 unknown), rsrp index 0-97 (255 unknown),
                sinr in half-dB steps (255 unknown). 3GPP TS 27.007 mappings.
  AT+XMCI=1  -> +XMCI: <type>,<mcc>,<mnc>,<tac>,<ci>,<pci>,<dl_earfcn>,<ul_earfcn>,...
                type 4/5 = serving LTE cell; dl_earfcn is a quoted hex field.

History note: this project first decoded the RPC channel's radio-signal
indication. Hardware correlation (2026-07-18) proved those fields were the
serving cell's IDENTITY (cell-id/PCI packed words) — constants that merely
looked like plausible RF values — while these AT queries return the actual
live measurements. The privacy rule stands: parse only measurements; never
return TAC/cell-id/PCI.
"""
import re

# DL EARFCN ranges -> LTE band. AT&T-operated bands only by default: every extra
# range is false-match surface. Extend deliberately for other carriers.
BAND_RANGES = [
    (600, 1199, 'B2', 1900), (1950, 2399, 'B4', 1700), (2400, 2649, 'B5', 850),
    (5010, 5179, 'B12', 700), (5280, 5379, 'B14', 700), (5730, 5849, 'B17', 700),
    (9660, 9769, 'B29', 700), (9770, 9869, 'B30', 2300),
    (66436, 67335, 'B66', 1700), (68586, 68935, 'B71', 600),
]

_XCESQ_RE = re.compile(
    r'\+XCESQ:\s*\d+,\s*\d+,\s*\d+,\s*\d+,\s*\d+,\s*(\d+),\s*(\d+),\s*(-?\d+)')
_XMCI_RE = re.compile(r'\+XMCI:\s*([0-9]+),(.*)')


def band_for_earfcn(earfcn):
    for lo, hi, name, _mhz in BAND_RANGES:
        if lo <= earfcn <= hi:
            return name
    return None


def freq_mhz_for_earfcn(earfcn):
    for lo, hi, _name, mhz in BAND_RANGES:
        if lo <= earfcn <= hi:
            return mhz
    return None


def quality_pct(rsrp_dbm):
    """Map RSRP -120..-80 dBm onto 0..100, clamped."""
    pct = (rsrp_dbm + 120.0) * (100.0 / 40.0)
    return int(max(0, min(100, round(pct))))


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
        out['rsrq_db'] = rsrq_i * 0.5 - 19.5
    if sinr != 255:
        out['snr_db'] = sinr / 2.0
    return out


def parse_xmci_earfcn(text):
    """Extract the serving LTE cell's DL EARFCN from an AT+XMCI response.
    Returns None unless a serving-cell line (type 4 or 5) parses cleanly."""
    for line_m in _XMCI_RE.finditer(text or ''):
        if line_m.group(1) not in ('4', '5'):
            continue
        # Fields after <type>: mcc, mnc, then quoted hex fields; dl_earfcn is
        # the 4th quoted field (tac, ci, pci, dl_earfcn, ul_earfcn, ...).
        quoted = re.findall(r'"0x([0-9A-Fa-f]+)"', line_m.group(2))
        if len(quoted) < 4:
            continue
        try:
            earfcn = int(quoted[3], 16)
        except ValueError:
            continue
        if 0 < earfcn < 70000:
            return earfcn
    return None
