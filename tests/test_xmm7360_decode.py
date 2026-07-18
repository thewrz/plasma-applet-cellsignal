import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360'))
from xmm7360_decode import (  # noqa: E402
    band_for_earfcn,
    freq_mhz_for_earfcn,
    parse_xcesq,
    parse_xmci_earfcn,
    quality_pct,
)

# Shapes of real responses captured on hardware 2026-07-18; identifiers
# (TAC/cell-id) replaced with synthetic values.
XCESQ_LIVE = '\r\n+XCESQ: 0,99,99,255,255,10,34,16\r\n\r\nOK\r\n'
XCESQ_UNKNOWN = '\r\n+XCESQ: 0,99,99,255,255,255,255,255\r\n\r\nOK\r\n'
XCESQ_NEG_SINR = '\r\n+XCESQ: 1,99,99,255,255,7,21,-9\r\n\r\nOK\r\n'
XMCI_LIVE = ('\r\n+XMCI: 4,310,410,"0x1111","0x01234567","0x003D","0x000002BC",'
             '"0x0000490C","0xFFFFFFFF",36,21,26,"0x0000001C","0x00000000"\r\n\r\nOK\r\n')


def test_parse_xcesq_live_sample():
    m = parse_xcesq(XCESQ_LIVE)
    assert m['rsrp_dbm'] == -107.0        # idx 34 -> idx - 141
    assert m['rsrq_db'] == -14.5          # idx 10 -> 0.5*idx - 19.5
    assert m['snr_db'] == 8.0             # sinr 16 in half-dB steps


def test_parse_xcesq_negative_sinr():
    m = parse_xcesq(XCESQ_NEG_SINR)
    assert m['rsrp_dbm'] == -120.0
    assert m['rsrq_db'] == -16.0
    assert m['snr_db'] == -4.5


def test_parse_xcesq_unknown_markers():
    assert parse_xcesq(XCESQ_UNKNOWN) == {'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None}


def test_parse_xcesq_garbage():
    empty = {'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None}
    assert parse_xcesq('ERROR') == empty
    assert parse_xcesq('') == empty


def test_parse_xmci_earfcn():
    assert parse_xmci_earfcn(XMCI_LIVE) == 700   # DL EARFCN field, hex 0x2BC


def test_parse_xmci_rejects_non_serving_and_garbage():
    assert parse_xmci_earfcn('+XMCI: 0,310,410,"0x1","0x2","0x3","0x00000004"') is None
    assert parse_xmci_earfcn('OK') is None
    assert parse_xmci_earfcn('') is None


def test_band_table():
    assert band_for_earfcn(700) == 'B2'
    assert freq_mhz_for_earfcn(700) == 1900
    assert band_for_earfcn(5110) == 'B12'
    assert band_for_earfcn(3000) is None


def test_quality_pct_clamps():
    assert quality_pct(-80.0) == 100
    assert quality_pct(-120.0) == 0
    assert quality_pct(-100.0) == 50
