import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360'))
from xmm7360_decode import decode_indication, band_for_earfcn, quality_pct  # noqa: E402

# Synthetic reconstruction of a real indication's TAIL STRUCTURE (values are the
# project's own published field map; no identifiers involved).
GROUP1 = [0, 64016, 0, 0, 61, 0, 16, 10, 48, 50, 1652, 0, 2606, 10, 48]
ZEROS = [0] * 15
SUMMARY = [3, 34, 97, 10, 48, 16, 50, 61, 5110, 0x674fa10, 0xff32003d,
           246, 1652, 64016, 61, 5110, 6, 116, 64016, 0]
SAMPLE = [0xffff, 0xffff, 255] * 20 + GROUP1 + ZEROS + SUMMARY


def test_decode_connected_sample():
    d = decode_indication(SAMPLE)
    assert d['rsrp_dbm'] == -95.0          # s16(64016)/16
    assert d['snr_db'] == 16.52            # 1652/100
    assert d['rsrq_db'] == -12.875         # hi16(0xff32003d) s16 /16
    assert d['earfcn'] == 5110 and d['band'] == 'B12' and d['freq_mhz'] == 700
    assert d['quality_pct'] == 62


def test_band_slots_must_agree():
    mismatched = SAMPLE[:-5] + [9999] + SAMPLE[-4:]
    d = decode_indication(mismatched)
    assert d['band'] is None and d['earfcn'] is None


def test_flickering_scan_freq_not_used_as_band():
    # 2606 (a B5-range scan frequency) sits in GROUP1; only the locked summary
    # slots may drive the band.
    assert decode_indication(SAMPLE)['band'] == 'B12'


def test_band_table():
    assert band_for_earfcn(700) == 'B2'
    assert band_for_earfcn(5110) == 'B12'
    assert band_for_earfcn(3000) is None   # B7 range — not an AT&T band


def test_quality_pct_clamps():
    assert quality_pct(-80.0) == 100
    assert quality_pct(-120.0) == 0
    assert quality_pct(-100.0) == 50


def test_decode_garbage_returns_nulls():
    d = decode_indication([1, 2, 3])
    assert d['rsrp_dbm'] is None and d['band'] is None
