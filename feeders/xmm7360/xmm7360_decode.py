"""Decode the XMM7360 UtaMsNetRadioSignalIndCb indication into signal metrics.

Field map (empirically derived by this project, validated across bands B2/B12 —
no upstream driver or ModemManager plugin decodes this indication):
  ints[-7]  as s16 / 16          -> RSRP dBm  (Intel Q4 fixed point)
  ints[-8]  as s16 / 100         -> SNR dB
  ints[-10] high 16 bits, s16/16 -> RSRQ dB
  ints[-12] == ints[-5]          -> serving-cell EARFCN (both slots must agree)
Earlier positions hold neighbor tables and per-tick scan frequencies — never
scan them for EARFCN-shaped values; they flicker and false-match band ranges.
"""

# DL EARFCN ranges -> LTE band. AT&T-operated bands only by default: every extra
# range is false-match surface. Extend deliberately for other carriers.
BAND_RANGES = [
    (600, 1199, 'B2', 1900), (1950, 2399, 'B4', 1700), (2400, 2649, 'B5', 850),
    (5010, 5179, 'B12', 700), (5280, 5379, 'B14', 700), (5730, 5849, 'B17', 700),
    (9660, 9769, 'B29', 700), (9770, 9869, 'B30', 2300),
    (66436, 67335, 'B66', 1700), (68586, 68935, 'B71', 600),
]


def _s16(v):
    return v - 0x10000 if 0x8000 <= v <= 0xffff else v


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


def decode_indication(ints):
    nums = [v for v in ints if isinstance(v, int)]
    out = {'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None,
           'band': None, 'earfcn': None, 'freq_mhz': None, 'quality_pct': None}
    if len(nums) < 12:
        return out

    cand = _s16(nums[-7]) if nums[-7] <= 0xffff else None
    if cand is not None and -2256 <= cand <= -640:            # -141..-40 dBm in Q4
        out['rsrp_dbm'] = cand / 16.0
        out['quality_pct'] = quality_pct(out['rsrp_dbm'])

    snr = _s16(nums[-8]) if nums[-8] <= 0xffff else None
    if snr is not None and -1000 <= snr <= 4000:              # -10..+40 dB centi-dB
        out['snr_db'] = snr / 100.0

    word = nums[-10]
    if word > 0xffff:
        hi = _s16((word >> 16) & 0xffff)
        if -544 <= hi <= 0:                                   # -34..0 dB in Q4
            out['rsrq_db'] = hi / 16.0

    if nums[-12] == nums[-5] and band_for_earfcn(nums[-12]):
        out['earfcn'] = nums[-12]
        out['band'] = band_for_earfcn(nums[-12])
        out['freq_mhz'] = freq_mhz_for_earfcn(nums[-12])
    return out
