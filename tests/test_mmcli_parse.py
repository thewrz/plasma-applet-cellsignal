import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'mmcli'))
from mmcli_parse import (  # noqa: E402
    best_tech,
    modem_indexes,
    parse_cell_info,
    parse_modem_info,
    parse_signal,
)

FIXTURES = pathlib.Path(__file__).parent.parent / 'feeders' / 'mmcli' / 'fixtures'


def load(name):
    return json.loads((FIXTURES / f'{name}.json').read_text())


LTE = load('lte-connected')
NR5G = load('nr5g-connected')
DISC = load('disconnected')
NOMODEM = load('no-modem')
MISSING = load('missing-cellinfo')


def test_modem_indexes():
    assert modem_indexes(LTE['list']) == [0]
    assert modem_indexes(NOMODEM['list']) == []
    assert modem_indexes({'modem-list': None}) == []
    assert modem_indexes({}) == []
    assert modem_indexes(None) == []
    assert modem_indexes(
        {'modem-list': ['/org/freedesktop/ModemManager1/Modem/2',
                        '/org/freedesktop/ModemManager1/Modem/7']}) == [2, 7]


def test_best_tech_priority():
    assert best_tech(['lte']) == ('lte', 'lte')
    assert best_tech(['5gnr']) == ('nr5g', '5g')
    assert best_tech(['lte', '5gnr']) == ('nr5g', '5g')   # highest generation wins
    assert best_tech(['hspa']) == ('umts', 'umts')
    assert best_tech(['edge']) == ('gsm', 'gsm')
    assert best_tech([]) == (None, None)
    assert best_tech(None) == (None, None)


def test_parse_modem_info_connected_lte():
    assert parse_modem_info(LTE['info']) == {
        'state': 'connected', 'tech': 'lte', 'operator': 'MOBILE'}


def test_parse_modem_info_nr5g():
    assert parse_modem_info(NR5G['info'])['tech'] == 'nr5g'


def test_parse_modem_info_disconnected_state():
    assert parse_modem_info(DISC['info'])['state'] == 'registered'


def test_parse_modem_info_empty():
    assert parse_modem_info(None) == {'state': None, 'tech': None, 'operator': None}
    assert parse_modem_info({'modem': {}}) == {
        'state': None, 'tech': None, 'operator': None}


def test_parse_modem_info_operator_placeholder_is_null():
    doc = {'modem': {'3gpp': {'operator-name': '--'},
                     'generic': {'state': 'connected', 'access-technologies': ['lte']}}}
    assert parse_modem_info(doc)['operator'] is None


def test_parse_modem_info_normalizes_placeholders_and_numeric_plmn():
    padded = {'modem': {'3gpp': {'operator-name': ' MOBILE '},
                        'generic': {'state': ' -- ', 'access-technologies': ['lte']}}}
    numeric = {'modem': {'3gpp': {'operator-name': '310410'},
                         'generic': {'state': ' connected ',
                                     'access-technologies': ['lte']}}}
    assert parse_modem_info(padded) == {
        'state': None, 'tech': 'lte', 'operator': 'MOBILE'}
    assert parse_modem_info(numeric) == {
        'state': 'connected', 'tech': 'lte', 'operator': None}


def test_parse_signal_lte():
    assert parse_signal(LTE['signal'], 'lte') == {
        'rsrp_dbm': -98.0, 'rsrq_db': -11.0, 'snr_db': 8.0, 'rssi_dbm': -65.0}


def test_parse_signal_nr5g_has_no_rssi():
    m = parse_signal(NR5G['signal'], 'nr5g')
    assert m['rsrp_dbm'] == -90.0 and m['rsrq_db'] == -10.0 and m['snr_db'] == 20.0
    assert m['rssi_dbm'] is None


def test_parse_signal_falls_back_across_techs():
    # Active tech reported as nr5g but only the lte dict carries a reading.
    m = parse_signal(LTE['signal'], 'nr5g')
    assert m['rsrp_dbm'] == -98.0


def test_parse_signal_prefers_active_gsm_rssi_over_stale_lte_rsrp():
    doc = {'modem': {'signal': {
        'gsm': {'rssi': '-73'},
        'lte': {'rsrp': '-110'},
    }}}
    assert parse_signal(doc, 'gsm') == {
        'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None, 'rssi_dbm': -73.0}


def test_parse_signal_all_unknown():
    doc = {'modem': {'signal': {'lte': {'rsrp': '--', 'rsrq': '--',
                                        'rssi': '--', 'snr': '--'}}}}
    assert parse_signal(doc, 'lte') == {
        'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None, 'rssi_dbm': None}
    assert parse_signal(None, 'lte')['rsrp_dbm'] is None


def test_parsers_treat_unexpected_json_shapes_as_unknown():
    empty_info = {'state': None, 'tech': None, 'operator': None}
    empty_signal = {
        'rsrp_dbm': None, 'rsrq_db': None, 'snr_db': None, 'rssi_dbm': None}
    empty_cell = {'earfcn': None, 'neighbors': []}

    assert modem_indexes([]) == []
    assert modem_indexes({'modem-list': {}}) == []
    assert parse_modem_info({'modem': []}) == empty_info
    assert parse_modem_info({'modem': {'generic': [], '3gpp': []}}) == empty_info
    assert parse_signal({'modem': None}, 'lte') == empty_signal
    assert parse_signal({'modem': {'signal': []}}, 'lte') == empty_signal
    assert parse_cell_info({'modem': []}) == empty_cell
    assert parse_cell_info({'modem': {'cell-info': {}}}) == empty_cell


def test_parse_cell_info_serving_and_neighbor():
    m = parse_cell_info(LTE['cellinfo'])
    assert m['earfcn'] == 5110
    assert m['neighbors'] == [
        {'band': 'B2', 'earfcn': 700, 'rsrp_dbm': -112.0, 'rsrq_db': -16.0}]


def test_parse_cell_info_nr5g_has_no_lte_earfcn():
    # A 5gnr serving cell exposes nrarfcn, not earfcn -> no LTE band derivation.
    m = parse_cell_info(NR5G['cellinfo'])
    assert m['earfcn'] is None and m['neighbors'] == []


def test_parse_cell_info_absent():
    assert parse_cell_info(None) == {'earfcn': None, 'neighbors': []}
    assert parse_cell_info(MISSING['cellinfo']) == {'earfcn': None, 'neighbors': []}
    assert parse_cell_info({'modem': {'cell-info': []}}) == {
        'earfcn': None, 'neighbors': []}


def test_parsers_expose_no_identifier_keys():
    # cell-info carries tac/ci/physical-ci; decoded output must expose none.
    assert set(parse_cell_info(LTE['cellinfo'])) == {'earfcn', 'neighbors'}
    for n in parse_cell_info(LTE['cellinfo'])['neighbors']:
        assert set(n) == {'band', 'earfcn', 'rsrp_dbm', 'rsrq_db'}
    assert set(parse_modem_info(LTE['info'])) == {'state', 'tech', 'operator'}
