import json
import pathlib

import pytest

FIXTURES = sorted(pathlib.Path(__file__).parent.parent.glob('fixtures/*.json'))

# v1 keeps its original shape; v2 is additive — new nullable top-level and
# cell fields. A v1 document must still validate, so the checks branch on
# `version`.
REQUIRED_TOP_V1 = {'version', 'ts', 'state', 'tech', 'metrics', 'cell', 'quality_pct', 'source'}
REQUIRED_TOP_V2 = REQUIRED_TOP_V1 | {'aggregation', 'neighbors', 'operator'}
METRIC_KEYS = {'rsrp_dbm', 'rsrq_db', 'snr_db', 'rssi_dbm'}
CELL_KEYS_V1 = {'band', 'earfcn', 'freq_mhz'}
CELL_KEYS_V2 = CELL_KEYS_V1 | {'bandwidth_mhz', 'timing_advance', 'distance_m', 'rrc_state'}
NEIGHBOR_KEYS = {'band', 'earfcn', 'rsrp_dbm', 'rsrq_db'}
AGGREGATION_KEYS = {'carriers', 'bands', 'aggregate_mhz'}
STATES = {'connected', 'disconnected', 'no-modem', 'error'}
FORBIDDEN_SUBSTRINGS = ('imei', 'iccid', 'imsi', 'cell_id', 'cellid', 'cid', 'tac', 'pci')

# Names kept for consumers that build the current (v2) document.
REQUIRED_TOP = REQUIRED_TOP_V2
CELL_KEYS = CELL_KEYS_V2


def _required_top(version):
    return REQUIRED_TOP_V2 if version >= 2 else REQUIRED_TOP_V1


def _cell_keys(version):
    return CELL_KEYS_V2 if version >= 2 else CELL_KEYS_V1


@pytest.mark.parametrize('path', FIXTURES, ids=lambda p: p.name)
def test_fixture_matches_contract(path):
    doc = json.loads(path.read_text())
    version = doc.get('version')
    assert version in (1, 2)
    assert _required_top(version).issubset(doc), \
        f'missing keys: {_required_top(version) - set(doc)}'
    assert doc['state'] in STATES
    assert METRIC_KEYS.issubset(doc['metrics'])
    assert _cell_keys(version).issubset(doc['cell'])
    for k in METRIC_KEYS:
        v = doc['metrics'][k]
        assert v is None or isinstance(v, (int, float))


@pytest.mark.parametrize('path', FIXTURES, ids=lambda p: p.name)
def test_v2_fixture_new_field_shapes(path):
    doc = json.loads(path.read_text())
    if doc.get('version') != 2:
        return
    agg = doc['aggregation']
    assert agg is None or AGGREGATION_KEYS.issubset(agg)
    assert isinstance(doc['neighbors'], list)
    for n in doc['neighbors']:
        assert NEIGHBOR_KEYS == set(n)
    assert doc['operator'] is None or isinstance(doc['operator'], str)


@pytest.mark.parametrize('path', FIXTURES, ids=lambda p: p.name)
def test_fixture_has_no_identifiers(path):
    lowered = path.read_text().lower()
    for bad in FORBIDDEN_SUBSTRINGS:
        assert bad not in lowered, f'{bad!r} found in {path.name}'


def test_fixtures_exist():
    assert len(FIXTURES) >= 5


def test_v2_fixtures_exist():
    v2 = [p for p in FIXTURES if json.loads(p.read_text()).get('version') == 2]
    assert len(v2) >= 3
