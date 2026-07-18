import importlib.util
import json
import pathlib
import sys
from importlib.machinery import SourceFileLoader

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360'))
from xmm7360_decode import parse_xcesq, parse_xmci_earfcn  # noqa: E402

from test_fixtures import (  # noqa: E402
    CELL_KEYS, FORBIDDEN_SUBSTRINGS, METRIC_KEYS, REQUIRED_TOP,
)
from test_xmm7360_decode import XCESQ_LIVE, XMCI_LIVE  # noqa: E402

FEEDER = pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360' / 'cellsignal-feeder-xmm7360'

DECODED = {'rsrp_dbm': -95.0, 'rsrq_db': -12.9, 'snr_db': 16.5,
           'band': 'B12', 'earfcn': 5110, 'freq_mhz': 700, 'quality_pct': 62}


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


def test_contract_key_sets_pinned_exactly():
    # Privacy guard: the published document's key sets are pinned so a new
    # field (e.g. pci/cell_id threaded through as an "extra key") fails here.
    m = load_feeder()
    for decoded, state in ((DECODED, 'connected'), (None, 'error'),
                           (None, 'no-modem'), (None, 'disconnected')):
        doc = m.build_contract(decoded, state, now=1)
        assert set(doc) == REQUIRED_TOP
        assert set(doc['metrics']) == METRIC_KEYS
        assert set(doc['cell']) == CELL_KEYS


def test_published_document_has_no_identifiers():
    m = load_feeder()
    lowered = json.dumps(m.build_contract(DECODED, 'connected', now=1)).lower()
    for bad in FORBIDDEN_SUBSTRINGS:
        assert bad not in lowered, f'{bad!r} found in published document'


def test_parser_output_has_no_identifier_keys():
    keys = ' '.join(parse_xcesq(XCESQ_LIVE)).lower()
    for bad in FORBIDDEN_SUBSTRINGS:
        assert bad not in keys, f'{bad!r} found in parser output keys'


def test_xmci_parser_returns_only_earfcn():
    # XMCI responses carry TAC/cell-id/PCI; the parser must expose none of them.
    assert parse_xmci_earfcn(XMCI_LIVE) == 700
