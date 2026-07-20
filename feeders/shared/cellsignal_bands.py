"""Shared EARFCN band/frequency table and quality mapping for Cell Signal feeders.

Every feeder derives the same LTE band label, nominal frequency and normalized
quality percentage from a downlink EARFCN and an RSRP reading, so those helpers
live here and are imported by each feeder (xmm7360, mmcli, ...) rather than being
copied. This module has no runtime dependencies and is installed alongside each
feeder script so it imports cleanly from the script's own directory.
"""

# DL EARFCN ranges -> LTE band. AT&T-operated bands only by default: every extra
# range is false-match surface. Extend deliberately for other carriers.
BAND_RANGES = [
    (600, 1199, 'B2', 1900), (1950, 2399, 'B4', 1700), (2400, 2649, 'B5', 850),
    (5010, 5179, 'B12', 700), (5280, 5379, 'B14', 700), (5730, 5849, 'B17', 700),
    (9660, 9769, 'B29', 700), (9770, 9869, 'B30', 2300),
    (66436, 67335, 'B66', 1700), (68586, 68935, 'B71', 600),
]


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
