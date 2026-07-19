import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360'))
from xmm7360_decode import (  # noqa: E402
    band_for_earfcn,
    distance_m,
    freq_mhz_for_earfcn,
    parse_cops_operator,
    parse_cscon,
    parse_gtcainfo,
    parse_xcesq,
    parse_xmci,
    quality_pct,
)

# Shapes of real responses captured on hardware 2026-07-18; identifiers
# (TAC/cell-id) replaced with synthetic values.
XCESQ_LIVE = '\r\n+XCESQ: 0,99,99,255,255,10,34,16\r\n\r\nOK\r\n'
XCESQ_UNKNOWN = '\r\n+XCESQ: 0,99,99,255,255,255,255,255\r\n\r\nOK\r\n'
XCESQ_NEG_SINR = '\r\n+XCESQ: 1,99,99,255,255,7,21,-9\r\n\r\nOK\r\n'
# Serving cell (type 4): dl_earfcn 0x2BC=700 (B2), trio 36,21,26, TA field 0x1C=28.
XMCI_LIVE = ('\r\n+XMCI: 4,310,410,"0x1111","0x01234567","0x003D","0x000002BC",'
             '"0x0000490C","0xFFFFFFFF",36,21,26,"0x0000001C","0x00000000"\r\n\r\nOK\r\n')
# Serving (type 4, TA 28) plus one neighbor (type 5): dl_earfcn 0x13F6=5110 (B12),
# trio 36,30,12, neighbor TA field 0x7FFFFFFF (N/A on neighbors).
XMCI_WITH_NEIGHBOR = (
    '\r\n+XMCI: 4,310,410,"0x1111","0x01234567","0x003D","0x000002BC",'
    '"0x0000490C","0xFFFFFFFF",36,21,26,"0x0000001C","0x00000000"'
    '\r\n+XMCI: 5,310,410,"0x2222","0x07654321","0x0041","0x000013F6",'
    '"0x0000490C","0x7FFFFFFF",36,30,12,"0x7FFFFFFF","0x00000000"\r\n\r\nOK\r\n')

# AT+GTCAINFO?: leading component-carrier count, then one line per carrier.
# PCell carries mcc/mnc/tac/cid (synthetic); SCell omits them. Fields end
# ...,dl_earfcn,ul_earfcn,dl_bw,ul_bw (bw codes 0..5 -> 1.4/3/5/10/15/20 MHz).
GTCAINFO_CA = (
    '\r\n+GTCAINFO: 2'
    '\r\n+GTCAINFO: 0,12,310,410,"0x1111","0x01234567",61,36,21,26,5110,23230,3,3'
    '\r\n+GTCAINFO: 1,2,297,42,25,10,700,18700,5,5'
    '\r\n\r\nOK\r\n')
GTCAINFO_SINGLE = (
    '\r\n+GTCAINFO: 1'
    '\r\n+GTCAINFO: 0,12,310,410,"0x1111","0x01234567",61,36,21,26,5110,23230,3,3'
    '\r\n\r\nOK\r\n')


def test_parse_xcesq_live_sample():
    m = parse_xcesq(XCESQ_LIVE)
    assert m['rsrp_dbm'] == -107.0        # idx 34 -> idx - 141
    assert m['rsrq_db'] == -15.0          # idx 10 -> 0.5*idx - 20 (bin lower bound)
    assert m['snr_db'] == 8.0             # sinr 16 in half-dB steps


def test_parse_xcesq_negative_sinr():
    m = parse_xcesq(XCESQ_NEG_SINR)
    assert m['rsrp_dbm'] == -120.0
    assert m['rsrq_db'] == -16.5
    assert m['snr_db'] == -4.5


def test_parse_xcesq_unknown_markers():
    assert parse_xcesq(XCESQ_UNKNOWN) == {'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None}


def test_parse_xcesq_garbage():
    empty = {'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None}
    assert parse_xcesq('ERROR') == empty
    assert parse_xcesq('') == empty


def test_parse_xmci_earfcn():
    assert parse_xmci(XMCI_LIVE)['earfcn'] == 700   # DL EARFCN field, hex 0x2BC


def test_parse_xmci_live_trio():
    # Trio fields are instantaneous measurements: (rsrp_idx, rsrq_idx, sinr_half)
    m = parse_xmci(XMCI_LIVE)                       # trio 36,21,26
    assert m['rsrp_dbm'] == -105.0                  # 36 - 141
    assert m['rsrq_db'] == -9.5                     # 0.5*21 - 20
    assert m['snr_db'] == 13.0                      # 26 / 2


def test_parse_xmci_weak_sample():
    weak = XMCI_LIVE.replace(',36,21,26,', ',30,15,18,')
    m = parse_xmci(weak)
    assert m['rsrp_dbm'] == -111.0 and m['rsrq_db'] == -12.5 and m['snr_db'] == 9.0


def test_parse_xmci_rejects_non_serving_and_garbage():
    empty = {'earfcn': None, 'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None,
             'timing_advance': None, 'neighbors': []}
    assert parse_xmci('+XMCI: 0,310,410,"0x1","0x2","0x3","0x00000004"') == empty
    assert parse_xmci('OK') == empty
    assert parse_xmci('') == empty


def test_parse_xmci_timing_advance():
    # Serving line field 12 (the quoted hex after the trio): 0x1C = 28.
    assert parse_xmci(XMCI_LIVE)['timing_advance'] == 28


def test_parse_xmci_timing_advance_absent_markers():
    # 0x7FFFFFFF (N/A) and 0 (idle, no data) both yield null TA.
    na = XMCI_LIVE.replace('"0x0000001C"', '"0x7FFFFFFF"')
    idle = XMCI_LIVE.replace('"0x0000001C"', '"0x00000000"')
    assert parse_xmci(na)['timing_advance'] is None
    assert parse_xmci(idle)['timing_advance'] is None


def test_parse_xmci_no_neighbors_on_serving_only():
    assert parse_xmci(XMCI_LIVE)['neighbors'] == []


def test_parse_xmci_neighbors():
    m = parse_xmci(XMCI_WITH_NEIGHBOR)
    assert m['earfcn'] == 700 and m['timing_advance'] == 28   # serving unchanged
    assert m['neighbors'] == [
        {'band': 'B12', 'earfcn': 5110, 'rsrp_dbm': -105.0, 'rsrq_db': -5.0},
    ]


def test_distance_m():
    assert distance_m(28) == 2188        # round(28 * 78.125) = round(2187.5)
    assert distance_m(1) == 78
    assert distance_m(0) is None         # idle TA -> no distance
    assert distance_m(None) is None


def test_parse_gtcainfo_carrier_aggregation():
    m = parse_gtcainfo(GTCAINFO_CA)
    assert m['carriers'] == 2
    assert m['bands'] == ['B12', 'B2']
    assert m['aggregate_mhz'] == 30                # 10 (PCell) + 20 (SCell)
    assert m['serving_bandwidth_mhz'] == 10        # PCell dl_bw code 3


def test_parse_gtcainfo_single_carrier():
    m = parse_gtcainfo(GTCAINFO_SINGLE)
    assert m['carriers'] == 1
    assert m['bands'] == ['B12']
    assert m['aggregate_mhz'] == 10
    assert m['serving_bandwidth_mhz'] == 10


def test_parse_gtcainfo_garbage():
    empty = {'carriers': None, 'bands': [], 'aggregate_mhz': None,
             'serving_bandwidth_mhz': None}
    assert parse_gtcainfo('OK') == empty
    assert parse_gtcainfo('') == empty


def test_parse_gtcainfo_exposes_no_identifiers():
    # tac/cid live in the PCell line; the decoded result must carry neither.
    m = parse_gtcainfo(GTCAINFO_CA)
    assert set(m) == {'carriers', 'bands', 'aggregate_mhz', 'serving_bandwidth_mhz'}


def test_parse_cscon():
    assert parse_cscon('\r\n+CSCON: 0,1\r\n\r\nOK\r\n') == 'connected'
    assert parse_cscon('\r\n+CSCON: 0,0\r\n\r\nOK\r\n') == 'idle'
    assert parse_cscon('+CSCON: 1') == 'connected'   # single-field fallback
    assert parse_cscon('ERROR') is None
    assert parse_cscon('') is None


def test_parse_cops_operator():
    assert parse_cops_operator('\r\n+COPS: 0,0,"MOBILE",7\r\n\r\nOK\r\n') == 'MOBILE'
    assert parse_cops_operator('+COPS: 0,2,"310410"') is None   # numeric PLMN, not a name
    assert parse_cops_operator('\r\n+COPS: 0\r\n\r\nOK\r\n') is None
    assert parse_cops_operator('') is None


def test_band_table():
    assert band_for_earfcn(700) == 'B2'
    assert freq_mhz_for_earfcn(700) == 1900
    assert band_for_earfcn(5110) == 'B12'
    assert band_for_earfcn(3000) is None


def test_quality_pct_clamps():
    assert quality_pct(-80.0) == 100
    assert quality_pct(-120.0) == 0
    assert quality_pct(-100.0) == 50
