import importlib.util
import json
import pathlib
import sys
from importlib.machinery import SourceFileLoader

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'mmcli'))

from test_fixtures import (  # noqa: E402
    CELL_KEYS, FORBIDDEN_SUBSTRINGS, METRIC_KEYS, REQUIRED_TOP,
)

FEEDER = pathlib.Path(__file__).parent.parent / 'feeders' / 'mmcli' / 'cellsignal-feeder-mmcli'
FIXTURES = pathlib.Path(__file__).parent.parent / 'feeders' / 'mmcli' / 'fixtures'


def load(name):
    return json.loads((FIXTURES / f'{name}.json').read_text())


def load_feeder():
    loader = SourceFileLoader('mmcli_feeder', str(FEEDER))
    spec = importlib.util.spec_from_loader('mmcli_feeder', loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def make_run_json(fixture):
    """Serve the fixture's per-call documents by mmcli argument vector."""
    def fake(args, debug=False):
        if args == ['-L']:
            return fixture.get('list')
        if '--signal-get' in args:
            return fixture.get('signal')
        if '--get-cell-info' in args:
            return fixture.get('cellinfo')
        if args[:2] == ['-m', '0'] and len(args) == 2:
            return fixture.get('info')
        return None
    return fake


def drive(monkeypatch, name):
    m = load_feeder()
    monkeypatch.setattr(m, 'run_json', make_run_json(load(name)))
    monkeypatch.setattr(m, 'enable_signal_polling', lambda *_a, **_k: None)
    return m, m.read_state()


def test_lte_connected_contract(monkeypatch):
    _m, (doc, keep) = drive(monkeypatch, 'lte-connected')
    assert keep is False
    assert doc['version'] == 2 and isinstance(doc['ts'], int)
    assert doc['state'] == 'connected' and doc['tech'] == 'lte'
    assert doc['metrics'] == {'rsrp_dbm': -98.0, 'rsrq_db': -11.0,
                              'snr_db': 8.0, 'rssi_dbm': -65.0}
    assert doc['cell'] == {'band': 'B12', 'earfcn': 5110, 'freq_mhz': 700,
                           'bandwidth_mhz': None, 'timing_advance': None,
                           'distance_m': None, 'rrc_state': None}
    assert doc['aggregation'] is None
    assert doc['neighbors'] == [{'band': 'B2', 'earfcn': 700,
                                 'rsrp_dbm': -112.0, 'rsrq_db': -16.0}]
    assert doc['operator'] == 'MOBILE'
    assert doc['quality_pct'] == 55           # (-98 + 120) * 2.5
    assert doc['source'] == 'mmcli'
    json.dumps(doc)


def test_nr5g_connected_contract(monkeypatch):
    _m, (doc, _keep) = drive(monkeypatch, 'nr5g-connected')
    assert doc['state'] == 'connected' and doc['tech'] == 'nr5g'
    assert doc['metrics']['rsrp_dbm'] == -90.0
    assert doc['metrics']['rssi_dbm'] is None
    assert doc['cell']['band'] is None and doc['cell']['earfcn'] is None
    assert doc['neighbors'] == []
    assert doc['operator'] == 'MOBILE'


def test_missing_cellinfo_still_publishes_metrics(monkeypatch):
    _m, (doc, _keep) = drive(monkeypatch, 'missing-cellinfo')
    assert doc['state'] == 'connected'
    assert doc['metrics']['rsrp_dbm'] == -105.0
    assert doc['cell']['band'] is None and doc['cell']['earfcn'] is None
    assert doc['cell']['freq_mhz'] is None
    assert doc['neighbors'] == []


def test_disconnected_contract(monkeypatch):
    _m, (doc, _keep) = drive(monkeypatch, 'disconnected')
    assert doc['state'] == 'disconnected' and doc['tech'] is None
    assert all(v is None for v in doc['metrics'].values())
    assert all(v is None for v in doc['cell'].values())
    assert doc['quality_pct'] is None and doc['operator'] is None
    assert doc['aggregation'] is None and doc['neighbors'] == []


def test_no_modem_contract(monkeypatch):
    _m, (doc, keep) = drive(monkeypatch, 'no-modem')
    assert keep is False and doc['state'] == 'no-modem'
    assert all(v is None for v in doc['metrics'].values())


def test_modemmanager_unreachable_keeps_last(monkeypatch):
    m = load_feeder()
    monkeypatch.setattr(m, 'run_json', lambda *_a, **_k: None)   # mmcli -L fails
    doc, keep = m.read_state()
    assert keep is True and doc is None


def test_connected_without_measurement_is_error(monkeypatch):
    # Connected, but every signal dict is unknown -> error, never a fabricated value.
    fixture = {
        'list': load('lte-connected')['list'],
        'info': load('lte-connected')['info'],
        'signal': {'modem': {'signal': {'lte': {'rsrp': '--', 'rsrq': '--',
                                                'rssi': '--', 'snr': '--'}}}},
        'cellinfo': load('lte-connected')['cellinfo'],
    }
    m = load_feeder()
    monkeypatch.setattr(m, 'run_json', make_run_json(fixture))
    monkeypatch.setattr(m, 'enable_signal_polling', lambda *_a, **_k: None)
    doc, keep = m.read_state()
    assert keep is False and doc['state'] == 'error'
    assert all(v is None for v in doc['metrics'].values())


def test_connected_gsm_publishes_rssi_without_rsrp(monkeypatch):
    fixture = {
        'list': {'modem-list': ['/org/freedesktop/ModemManager1/Modem/0']},
        'info': {'modem': {
            'generic': {'state': 'connected', 'access-technologies': ['gsm']},
            '3gpp': {'operator-name': 'MOBILE'},
        }},
        'signal': {'modem': {'signal': {'gsm': {'rssi': '-73'}}}},
        'cellinfo': None,
    }
    m = load_feeder()
    monkeypatch.setattr(m, 'run_json', make_run_json(fixture))
    monkeypatch.setattr(m, 'enable_signal_polling', lambda *_a, **_k: None)

    doc, keep = m.read_state()

    assert keep is False and doc['state'] == 'connected' and doc['tech'] == 'gsm'
    assert doc['metrics']['rssi_dbm'] == -73.0
    assert doc['metrics']['rsrp_dbm'] is None and doc['quality_pct'] is None


def test_connected_modem_is_selected_from_multiple_devices(monkeypatch):
    m = load_feeder()

    def fake(args, debug=False):
        if args == ['-L']:
            return {'modem-list': ['/org/freedesktop/ModemManager1/Modem/0',
                                   '/org/freedesktop/ModemManager1/Modem/1']}
        if args == ['-m', '0']:
            return {'modem': {'generic': {'state': 'registered'}}}
        if args == ['-m', '1']:
            return {'modem': {
                'generic': {'state': 'connected', 'access-technologies': ['lte']},
                '3gpp': {'operator-name': 'MOBILE'},
            }}
        if args == ['-m', '1', '--signal-get']:
            return {'modem': {'signal': {'lte': {'rsrp': '-91'}}}}
        if args == ['-m', '1', '--get-cell-info']:
            return {'modem': {'cell-info': []}}
        return None

    monkeypatch.setattr(m, 'run_json', fake)
    doc, keep = m.read_state()

    assert keep is False and doc['state'] == 'connected'
    assert doc['metrics']['rsrp_dbm'] == -91.0


def test_failed_modem_info_query_keeps_last_document(monkeypatch):
    m = load_feeder()
    monkeypatch.setattr(
        m, 'run_json',
        lambda args, debug=False: (
            {'modem-list': ['/org/freedesktop/ModemManager1/Modem/0']}
            if args == ['-L'] else None))

    doc, keep = m.read_state()

    assert keep is True and doc is None


def test_timestamp_is_captured_after_measurement_queries(monkeypatch):
    m = load_feeder()
    fixture = load('lte-connected')
    clock = {'now': 100}
    original_fake = make_run_json(fixture)

    def advancing_fake(args, debug=False):
        clock['now'] += 4
        return original_fake(args, debug)

    monkeypatch.setattr(m, 'run_json', advancing_fake)
    monkeypatch.setattr(m.time, 'time', lambda: clock['now'])

    doc, _keep = m.read_state()

    assert doc['ts'] == 116


def test_earfcn_zero_is_passed_to_band_derivation(monkeypatch):
    m = load_feeder()

    def fake(args, debug=False):
        if '--signal-get' in args:
            return {'modem': {'signal': {'lte': {'rsrp': '-90'}}}}
        return {'modem': {'cell-info': [
            {'cell-type': 'lte', 'serving': 'yes', 'earfcn': 0}]}}

    monkeypatch.setattr(m, 'run_json', fake)
    monkeypatch.setattr(m, 'band_for_earfcn', lambda earfcn: f'B{earfcn}')
    monkeypatch.setattr(m, 'freq_mhz_for_earfcn', lambda earfcn: earfcn)

    decoded = m.query_modem(0, 'lte', False)

    assert decoded['band'] == 'B0' and decoded['freq_mhz'] == 0


def test_contract_key_sets_pinned(monkeypatch):
    # Privacy guard: pin the published key sets so no identifier can slip in as
    # an extra key.
    for name in ('lte-connected', 'nr5g-connected', 'disconnected', 'no-modem'):
        _m, (doc, _keep) = drive(monkeypatch, name)
        assert set(doc) == REQUIRED_TOP
        assert set(doc['metrics']) == METRIC_KEYS
        assert set(doc['cell']) == CELL_KEYS


def test_published_document_has_no_identifiers(monkeypatch):
    # The raw LTE and NR fixtures carry tac/ci/physical-ci; none may reach output.
    for name in ('lte-connected', 'nr5g-connected'):
        _m, (doc, _keep) = drive(monkeypatch, name)
        lowered = json.dumps(doc).lower()
        for bad in FORBIDDEN_SUBSTRINGS:
            assert bad not in lowered, f'{bad!r} found in {name} output'
