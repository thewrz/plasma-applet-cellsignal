import importlib.util
import json
import pathlib
from importlib.machinery import SourceFileLoader

FEEDER = pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360' / 'cellsignal-feeder-xmm7360'


def load_feeder():
    loader = SourceFileLoader('feeder', str(FEEDER))
    spec = importlib.util.spec_from_loader('feeder', loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def test_build_contract_connected():
    m = load_feeder()
    decoded = {'rsrp_dbm': -95.0, 'rsrq_db': -12.9, 'snr_db': 16.5,
               'band': 'B12', 'earfcn': 5110, 'freq_mhz': 700, 'quality_pct': 62}
    doc = m.build_contract(decoded, 'connected', now=1789000000)
    assert doc['version'] == 1 and doc['ts'] == 1789000000
    assert doc['state'] == 'connected' and doc['tech'] == 'lte'
    assert doc['metrics']['rsrp_dbm'] == -95.0
    assert doc['metrics']['rssi_dbm'] is None
    assert doc['cell'] == {'band': 'B12', 'earfcn': 5110, 'freq_mhz': 700}
    assert doc['source'] == 'xmm7360'
    json.dumps(doc)  # serializable


def test_build_contract_down_states():
    m = load_feeder()
    for state in ('disconnected', 'no-modem', 'error'):
        doc = m.build_contract(None, state, now=5)
        assert doc['state'] == state and doc['tech'] is None
        assert all(v is None for v in doc['metrics'].values())
        assert doc['quality_pct'] is None
