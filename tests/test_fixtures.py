import json
import pathlib

import pytest

FIXTURES = sorted(pathlib.Path(__file__).parent.parent.glob('fixtures/*.json'))
REQUIRED_TOP = {'version', 'ts', 'state', 'tech', 'metrics', 'cell', 'quality_pct', 'source'}
METRIC_KEYS = {'rsrp_dbm', 'rsrq_db', 'snr_db', 'rssi_dbm'}
CELL_KEYS = {'band', 'earfcn', 'freq_mhz'}
STATES = {'connected', 'disconnected', 'no-modem', 'error'}
FORBIDDEN_SUBSTRINGS = ('imei', 'iccid', 'imsi', 'cell_id', 'cellid', 'tac', 'pci')


@pytest.mark.parametrize('path', FIXTURES, ids=lambda p: p.name)
def test_fixture_matches_contract(path):
    doc = json.loads(path.read_text())
    assert REQUIRED_TOP.issubset(doc), f'missing keys: {REQUIRED_TOP - set(doc)}'
    assert doc['version'] == 1
    assert doc['state'] in STATES
    assert METRIC_KEYS.issubset(doc['metrics'])
    assert CELL_KEYS.issubset(doc['cell'])
    for k in METRIC_KEYS:
        v = doc['metrics'][k]
        assert v is None or isinstance(v, (int, float))


@pytest.mark.parametrize('path', FIXTURES, ids=lambda p: p.name)
def test_fixture_has_no_identifiers(path):
    lowered = path.read_text().lower()
    for bad in FORBIDDEN_SUBSTRINGS:
        assert bad not in lowered, f'{bad!r} found in {path.name}'


def test_fixtures_exist():
    assert len(FIXTURES) >= 5
