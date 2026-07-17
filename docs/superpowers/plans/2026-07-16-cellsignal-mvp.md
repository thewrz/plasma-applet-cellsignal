# Cell Signal MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship phase-1 of the approved spec — a working Plasma 6 "Cell Signal" widget on wrz-p52's panel, fed live XMM7360 metrics through the JSON contract.

**Architecture:** Three decoupled units: (1) a normative JSON contract + synthetic fixtures, (2) a root-run xmm7360 feeder (RPC session → decode → `/run/cellsignal.json`, systemd timer), (3) a pure-QML plasmoid that execs a configurable feed command on a Timer and renders bars + live sparkline (compact) and a metric-detail popup (full). The contract is the only coupling.

**Tech Stack:** Python 3 (feeder, pytest), QML/Plasma 6 (`PlasmoidItem`, `org.kde.plasma.plasma5support` executable engine, `Kirigami.Theme`), KConfigXT, systemd, bash (install/build).

## Global Constraints

- License: MIT. No code copied from GPL projects (plasma-nm, modem-manager-gui, luci-app-modeminfo2 are reference-only).
- Privacy: no IMEI/ICCID/IMSI anywhere in repo, fixtures, tests, or published JSON; no cell-ID/TAC/PCI in contract v1. Fixtures use synthetic metric values.
- Plasmoid: pure QML only (no C++); `metadata.json` must carry `"KPackageStructure": "Plasma/Applet"` and `"X-Plasma-API-Minimum-Version": "6.0"`; Id `com.github.thewrz.cellsignal`.
- Theme: zero hardcoded colors — `Kirigami.Theme.*` only.
- Git: never commit to `main`; branch `feat/…`, draft PRs, Conventional Commits, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Two PRs: Tasks 1–3 → PR "feat: JSON contract + xmm7360 feeder"; Tasks 4–7 → PR "feat: plasmoid MVP". Task 8 is deployment (no PR).
- The feeder adapts the validated decode from `~/.config/dotfiles/lte/lte-signal` (this machine) — field map: `ints[-7]` s16/16 → RSRP dBm; `ints[-8]` s16/100 → SNR dB; `ints[-10]` hi-16 s16/16 → RSRQ dB; `ints[-12]==ints[-5]` → serving EARFCN.

---

### Task 0: Branch + issues

**Files:** none (git/gh only)

- [ ] **Step 1: Create issues and branch**

```bash
cd ~/github/plasma-applet-cellsignal
gh issue create --title "Contract v1 + xmm7360 feeder" --body "JSON contract doc, synthetic fixtures, xmm7360 feeder with tests. Phase 1 of docs/superpowers/specs/2026-07-16-cellsignal-design.md"
gh issue create --title "Plasmoid MVP (sparkline panel + popup + config)" --body "Pure-QML Plasma 6 widget per spec. Phase 1."
git checkout -b feat/contract-and-feeder
```

---

### Task 1: Contract doc + fixtures + validator test

**Files:**
- Create: `docs/CONTRACT.md`
- Create: `fixtures/connected-lte.json`, `fixtures/weak-signal.json`, `fixtures/disconnected.json`, `fixtures/no-modem.json`, `fixtures/partial-metrics.json`
- Test: `tests/test_fixtures.py`

**Interfaces:**
- Produces: the contract keys every later task consumes: top-level `version:int=1, ts:int, state:str, tech:str|null, metrics:{rsrp_dbm,rsrq_db,snr_db,rssi_dbm: float|null}, cell:{band:str|null, earfcn:int|null, freq_mhz:int|null}, quality_pct:int|null, source:str`. `state ∈ {connected,disconnected,no-modem,error}`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_fixtures.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/github/plasma-applet-cellsignal && python3 -m pytest tests/ -v`
Expected: FAIL (`test_fixtures_exist` — no fixtures yet).

- [ ] **Step 3: Write the fixtures**

`fixtures/connected-lte.json`:
```json
{
  "version": 1,
  "ts": 1789000000,
  "state": "connected",
  "tech": "lte",
  "metrics": { "rsrp_dbm": -95.4, "rsrq_db": -9.8, "snr_db": 16.5, "rssi_dbm": null },
  "cell": { "band": "B12", "earfcn": 5110, "freq_mhz": 700 },
  "quality_pct": 62,
  "source": "fixture"
}
```

`fixtures/weak-signal.json`:
```json
{
  "version": 1,
  "ts": 1789000000,
  "state": "connected",
  "tech": "lte",
  "metrics": { "rsrp_dbm": -117.0, "rsrq_db": -17.5, "snr_db": -2.0, "rssi_dbm": null },
  "cell": { "band": "B2", "earfcn": 700, "freq_mhz": 1900 },
  "quality_pct": 8,
  "source": "fixture"
}
```

`fixtures/disconnected.json`:
```json
{
  "version": 1,
  "ts": 1789000000,
  "state": "disconnected",
  "tech": null,
  "metrics": { "rsrp_dbm": null, "rsrq_db": null, "snr_db": null, "rssi_dbm": null },
  "cell": { "band": null, "earfcn": null, "freq_mhz": null },
  "quality_pct": null,
  "source": "fixture"
}
```

`fixtures/no-modem.json`: same shape as `disconnected.json` but `"state": "no-modem"`.

`fixtures/partial-metrics.json`: same shape as `connected-lte.json` but `"rsrq_db": null, "snr_db": null` and `"cell": { "band": null, "earfcn": null, "freq_mhz": null }, "quality_pct": 40`.

- [ ] **Step 4: Write `docs/CONTRACT.md`**

```markdown
# Cell Signal feed contract — v1

A feeder publishes ONE JSON document (typically to `/run/cellsignal.json`,
world-readable). The widget executes a configurable command (default
`cat /run/cellsignal.json`) and parses stdout. This document is normative.

## Document

| Key | Type | Meaning |
|---|---|---|
| `version` | int | Contract version. This document: `1`. |
| `ts` | int | Unix seconds when the measurement was taken. Widgets treat docs older than 3 poll intervals as stale. |
| `state` | string | `connected` \| `disconnected` \| `no-modem` \| `error`. |
| `tech` | string\|null | Access technology (`lte`, `nr5g`, `umts`, …). |
| `metrics.rsrp_dbm` | number\|null | LTE/NR Reference Signal Received Power, dBm. |
| `metrics.rsrq_db` | number\|null | Reference Signal Received Quality, dB. |
| `metrics.snr_db` | number\|null | Signal-to-noise ratio, dB. |
| `metrics.rssi_dbm` | number\|null | Received Signal Strength Indicator, dBm. |
| `cell.band` | string\|null | Band label, e.g. `B12`, `n71`. |
| `cell.earfcn` | int\|null | Downlink (E)ARFCN. |
| `cell.freq_mhz` | int\|null | Nominal band frequency label in MHz. |
| `quality_pct` | int\|null | Normalized 0–100 overall quality (feeder-defined). |
| `source` | string | Feeder identifier, e.g. `xmm7360`, `mmcli`. |

Rules:
- Unknown values are `null` — never fabricated.
- Extra keys are allowed; consumers MUST ignore unknown keys (forward compatibility).
- **Privacy:** the contract has no fields for device or subscriber identifiers
  (IMEI/ICCID/IMSI) and none may be added. Cell identifiers (cell-ID/TAC/PCI) are
  excluded from v1; adding them requires a version bump and opt-in feeder config.

## Writing a feeder

Emit the document atomically (write temp file, `rename()`), any cadence ≥1s.
Run with the least privilege your hardware allows. See `feeders/` for examples.
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `python3 -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add docs/CONTRACT.md fixtures/ tests/test_fixtures.py
git commit -m "feat: contract v1, synthetic fixtures, fixture validator

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: xmm7360 decode module (pure logic, TDD)

**Files:**
- Create: `feeders/xmm7360/xmm7360_decode.py`
- Test: `tests/test_xmm7360_decode.py`

**Interfaces:**
- Produces: `decode_indication(ints: list[int]) -> dict` returning `{'rsrp_dbm': float|None, 'rsrq_db': float|None, 'snr_db': float|None, 'band': str|None, 'earfcn': int|None, 'freq_mhz': int|None, 'quality_pct': int|None}`. Also `band_for_earfcn(earfcn:int) -> str|None`, `quality_pct(rsrp_dbm:float) -> int`.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_xmm7360_decode.py
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
```

- [ ] **Step 2: Run to verify FAIL** — `python3 -m pytest tests/test_xmm7360_decode.py -v` → import error.

- [ ] **Step 3: Implement `feeders/xmm7360/xmm7360_decode.py`**

```python
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
    if cand is not None and -2256 <= cand <= -640:            # −141..−40 dBm in Q4
        out['rsrp_dbm'] = cand / 16.0
        out['quality_pct'] = quality_pct(out['rsrp_dbm'])

    snr = _s16(nums[-8]) if nums[-8] <= 0xffff else None
    if snr is not None and -1000 <= snr <= 4000:              # −10..+40 dB centi-dB
        out['snr_db'] = snr / 100.0

    word = nums[-10]
    if word > 0xffff:
        hi = _s16((word >> 16) & 0xffff)
        if -544 <= hi <= 0:                                   # −34..0 dB in Q4
            out['rsrq_db'] = hi / 16.0

    if nums[-12] == nums[-5] and band_for_earfcn(nums[-12]):
        out['earfcn'] = nums[-12]
        out['band'] = band_for_earfcn(nums[-12])
        out['freq_mhz'] = freq_mhz_for_earfcn(nums[-12])
    return out
```

- [ ] **Step 4: Run to verify PASS** — `python3 -m pytest tests/test_xmm7360_decode.py -v`

- [ ] **Step 5: Commit** — `git add feeders/xmm7360/xmm7360_decode.py tests/test_xmm7360_decode.py && git commit -m "feat: xmm7360 indication decoder (validated field map)" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"`

---

### Task 3: xmm7360 feeder main + contract writer + systemd units

**Files:**
- Create: `feeders/xmm7360/cellsignal-feeder-xmm7360` (executable python)
- Create: `feeders/xmm7360/cellsignal-xmm7360.service`, `feeders/xmm7360/cellsignal-xmm7360.timer`, `feeders/xmm7360/README.md`
- Test: `tests/test_contract_builder.py`

**Interfaces:**
- Consumes: `decode_indication(ints)` from Task 2.
- Produces: `build_contract(decoded: dict, state: str, now: int) -> dict` (contract v1 doc); CLI `cellsignal-feeder-xmm7360 [--print|--write|--debug]` writing `/run/cellsignal.json`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_contract_builder.py
import json
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360'))
import importlib.util

_spec = importlib.util.spec_from_loader('feeder', None)
FEEDER = pathlib.Path(__file__).parent.parent / 'feeders' / 'xmm7360' / 'cellsignal-feeder-xmm7360'


def load_feeder():
    from importlib.machinery import SourceFileLoader
    return SourceFileLoader('feeder', str(FEEDER)).load_module()


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
```

- [ ] **Step 2: Run to verify FAIL** — `python3 -m pytest tests/test_contract_builder.py -v` → loader error (file missing).

- [ ] **Step 3: Implement `feeders/xmm7360/cellsignal-feeder-xmm7360`** (mode 0755)

```python
#!/usr/bin/env python3
"""cellsignal feeder for the Intel XMM7360 (iosm + xmm7360-pci-spat userspace).

Publishes Cell Signal contract-v1 JSON (see docs/CONTRACT.md) to /run/cellsignal.json.
Per tick: flock the shared modem lock, open the RPC port, drain stale messages,
enable radio-signal reporting, catch one UtaMsNetRadioSignalIndCb, disable, close.
Never publishes device/subscriber identifiers — metrics only, by contract.

usage: cellsignal-feeder-xmm7360 [--print|--write|--debug]
"""
import contextlib
import fcntl
import io
import json
import os
import select
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xmm7360_decode import decode_indication  # noqa: E402

RPC_DIR = '/usr/lib/xmm7360-pci-spat/rpc'
sys.path.insert(0, RPC_DIR)

OUT = '/run/cellsignal.json'
LOCK = '/run/lte.lock'          # shared with the lte wrapper on this host
IFACE = 'wwan0'
RPC_NODE = '/dev/wwan0xmmrpc0'
IND_NAME = 'UtaMsNetRadioSignalIndCb'
SETTER = 'UtaMsNetSetRadioSignalReporting'
IND_WAIT_SECS = 6


class Timeout(Exception):
    pass


def _alarm(signum, frame):
    raise Timeout()


def with_timeout(secs, fn, *args, **kw):
    signal.signal(signal.SIGALRM, _alarm)
    signal.alarm(secs)
    try:
        return fn(*args, **kw)
    finally:
        signal.alarm(0)


def build_contract(decoded, state, now):
    d = decoded or {}
    connected = state == 'connected'
    return {
        'version': 1,
        'ts': now,
        'state': state,
        'tech': 'lte' if connected else None,
        'metrics': {
            'rsrp_dbm': d.get('rsrp_dbm'),
            'rsrq_db': d.get('rsrq_db'),
            'snr_db': d.get('snr_db'),
            'rssi_dbm': None,
        },
        'cell': {
            'band': d.get('band'),
            'earfcn': d.get('earfcn'),
            'freq_mhz': d.get('freq_mhz'),
        },
        'quality_pct': d.get('quality_pct'),
        'source': 'xmm7360',
    }


def iface_up():
    r = subprocess.run(['ip', '-4', '-o', 'addr', 'show', 'dev', IFACE],
                       capture_output=True, text=True)
    return 'inet ' in r.stdout


def drain_port(fd, quiet_secs=0.4, max_secs=3.0):
    start = time.time()
    while time.time() - start < max_secs:
        readable, _, _ = select.select([fd], [], [], quiet_secs)
        if not readable:
            return
        try:
            os.read(fd, 131072)
        except OSError:
            return


def catch_indication(debug=False):
    import rpc                 # noqa: E402
    import rpc_unsol_table     # noqa: E402
    ind_code = next(code for code, name in rpc_unsol_table.xmm7360_unsol.items()
                    if name == IND_NAME)
    quiet = io.StringIO()
    r = with_timeout(6, rpc.XMMRPC)
    ints = None
    try:
        drain_port(r.fp)
        with contextlib.redirect_stdout(sys.stderr if debug else quiet):
            with_timeout(6, r.execute, SETTER, rpc.asn_int4(1))
        end = time.time() + IND_WAIT_SECS
        while time.time() < end:
            readable, _, _ = select.select([r.fp], [], [], 0.3)
            if not readable:
                continue
            msg = with_timeout(5, os.read, r.fp, 131072)
            parsed = r.handle_message(msg)
            if parsed['type'] == 'unsolicited' and parsed['code'] == ind_code:
                ints = parsed['content']
                break
    finally:
        try:
            with contextlib.redirect_stdout(sys.stderr if debug else quiet):
                with_timeout(4, r.execute, SETTER, rpc.asn_int4(0))
        except Exception:
            pass
        try:
            os.close(r.fp)
        except OSError:
            pass
    return ints


def read_state(debug=False):
    """Return (contract_doc | None, keep_last: bool)."""
    now = int(time.time())
    if not os.path.exists(RPC_NODE):
        return build_contract(None, 'no-modem', now), False
    if not iface_up():
        return build_contract(None, 'disconnected', now), False

    lock = open(LOCK, 'w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return None, True
    try:
        try:
            ints = catch_indication(debug)
        except (Timeout, OSError) as e:
            print(f'cellsignal-feeder: rpc session failed ({type(e).__name__}: {e}); '
                  f'keeping last value', file=sys.stderr)
            return None, True
    finally:
        lock.close()

    if not ints:
        return build_contract(None, 'error', now), False
    decoded = decode_indication(ints)
    if decoded['rsrp_dbm'] is None:
        return build_contract(None, 'error', now), False
    return build_contract(decoded, 'connected', now), False


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else '--print'
    if mode not in ('--print', '--write', '--debug'):
        sys.exit(f'usage: cellsignal-feeder-xmm7360 [--print|--write|--debug]  (--write -> {OUT})')
    if os.geteuid() != 0:
        sys.exit('cellsignal-feeder-xmm7360: needs root for the RPC port')
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))

    doc, keep_last = read_state(debug=(mode == '--debug'))
    if keep_last:
        if mode != '--write':
            print('(modem busy — kept last value)')
        return
    text = json.dumps(doc)
    if mode == '--write':
        tmp = f'{OUT}.new'
        with open(tmp, 'w') as f:
            f.write(text + '\n')
        os.chmod(tmp, 0o644)
        os.replace(tmp, OUT)
    else:
        print(text)


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Run to verify PASS** — `python3 -m pytest tests/ -v` (all tests).

- [ ] **Step 5: systemd units + README**

`feeders/xmm7360/cellsignal-xmm7360.service`:
```ini
[Unit]
Description=Publish XMM7360 cellular metrics to /run/cellsignal.json (Cell Signal feeder)
ConditionPathExists=/dev/wwan0xmmrpc0

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cellsignal-feeder-xmm7360 --write
```

`feeders/xmm7360/cellsignal-xmm7360.timer`:
```ini
[Unit]
Description=Refresh Cell Signal metrics feed

[Timer]
OnBootSec=30
OnUnitActiveSec=2
AccuracySec=1

[Install]
WantedBy=timers.target
```

`feeders/xmm7360/README.md`:
```markdown
# xmm7360 feeder

For Intel XMM7360 modems driven by the in-tree `iosm` module + the
`xmm7360-pci-spat` userspace RPC tooling (expected at
`/usr/lib/xmm7360-pci-spat/rpc/`). Root required (the wwan RPC node is 0600).

Install:
    sudo install -Dm755 cellsignal-feeder-xmm7360 /usr/local/bin/cellsignal-feeder-xmm7360
    sudo install -Dm755 xmm7360_decode.py /usr/local/bin/xmm7360_decode.py
    sudo install -Dm644 cellsignal-xmm7360.service /etc/systemd/system/cellsignal-xmm7360.service
    sudo install -Dm644 cellsignal-xmm7360.timer   /etc/systemd/system/cellsignal-xmm7360.timer
    sudo systemctl daemon-reload && sudo systemctl enable --now cellsignal-xmm7360.timer
    cat /run/cellsignal.json

Privacy: publishes signal metrics only — never IMEI/ICCID/IMSI or cell identifiers.
```

Note: the feeder imports `xmm7360_decode` from its own directory; installing both
files to `/usr/local/bin` keeps that working (`sys.path` insert of script dir).

- [ ] **Step 6: Commit, push, open draft PR**

```bash
git add feeders/ tests/test_contract_builder.py
git commit -m "feat: xmm7360 feeder — contract JSON to /run/cellsignal.json

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin feat/contract-and-feeder
gh pr create --draft --title "feat: JSON contract v1 + xmm7360 feeder" --body "## Why
Foundations for the Cell Signal widget: the modem-agnostic feed contract and the first feeder.

## What
- docs/CONTRACT.md (contract v1) + synthetic fixtures + validator tests
- xmm7360 decoder module (validated field map) + feeder CLI + systemd units

## Testing
- [ ] pytest green (fixtures, decoder, contract builder)
- [ ] manual: --print on wrz-p52 emits valid JSON

🤖 Co-authored by Claude Fable 5. Closes #1."
```

---

### Task 4: Plasmoid skeleton (metadata, config schema, data plumbing)

**Files:**
- Create: `package/metadata.json`, `package/contents/config/main.xml`, `package/contents/config/config.qml`, `package/contents/ui/main.qml`
- Create: `install.sh`

**Interfaces:**
- Produces: root `PlasmoidItem` with `property var feed` (parsed contract or null), `property bool stale`, `property var history` (array of numbers for the sparkline), `function metricValue(doc, name)`. Consumed by Tasks 5–6 components via `root.*`.

- [ ] **Step 1: Branch** — `git checkout main && git pull && git checkout -b feat/plasmoid-mvp`

- [ ] **Step 2: `package/metadata.json`**

```json
{
    "KPackageStructure": "Plasma/Applet",
    "KPlugin": {
        "Authors": [{ "Email": "wrz@wrzdj.com", "Name": "Adam (thewrz)" }],
        "Category": "System Information",
        "Description": "Live cellular signal metrics: bars, sparkline, RSRP/RSRQ/SNR, band and frequency. Modem-agnostic via a simple JSON feed.",
        "Icon": "network-mobile-80",
        "Id": "com.github.thewrz.cellsignal",
        "License": "MIT",
        "Name": "Cell Signal",
        "Version": "0.1.0",
        "Website": "https://github.com/thewrz/plasma-applet-cellsignal"
    },
    "X-Plasma-API-Minimum-Version": "6.0"
}
```

- [ ] **Step 3: `package/contents/config/main.xml`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg xmlns="http://www.kde.org/standards/kcfg/1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://www.kde.org/standards/kcfg/1.0 http://www.kde.org/standards/kcfg/1.0/kcfg.xsd">
  <kcfgfile name=""/>
  <group name="General">
    <entry name="feedCommand" type="String"><default>cat /run/cellsignal.json</default></entry>
    <entry name="pollInterval" type="Int"><default>2</default></entry>
    <entry name="showBars" type="Bool"><default>true</default></entry>
    <entry name="showSparkline" type="Bool"><default>true</default></entry>
    <entry name="showBand" type="Bool"><default>true</default></entry>
    <entry name="showFrequency" type="Bool"><default>false</default></entry>
    <entry name="showTech" type="Bool"><default>false</default></entry>
    <entry name="showRsrp" type="Bool"><default>true</default></entry>
    <entry name="showRsrq" type="Bool"><default>true</default></entry>
    <entry name="showSnr" type="Bool"><default>true</default></entry>
    <entry name="showRssi" type="Bool"><default>false</default></entry>
    <entry name="sparklineMetric" type="String"><default>rsrp_dbm</default></entry>
    <entry name="sparklineWindow" type="Int"><default>60</default></entry>
  </group>
</kcfg>
```

- [ ] **Step 4: `package/contents/config/config.qml`**

```qml
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "network-mobile-80"
        source: "configGeneral.qml"
    }
}
```

- [ ] **Step 5: `package/contents/ui/main.qml`**

```qml
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Parsed contract doc (or null before first read / on parse failure)
    property var feed: null
    // Feed considered stale when older than 3 poll intervals or command failed
    property bool stale: true
    // Sparkline ring buffer of the configured metric
    property var history: []

    readonly property int pollInterval: Math.max(1, plasmoid.configuration.pollInterval)
    readonly property bool connected: feed !== null && feed.state === "connected" && !stale

    toolTipMainText: i18n("Cell Signal")
    toolTipSubText: {
        if (!feed) return i18n("no feed")
        if (feed.state !== "connected") return feed.state
        var parts = []
        if (feed.metrics.rsrp_dbm !== null) parts.push("RSRP " + feed.metrics.rsrp_dbm.toFixed(0) + " dBm")
        if (feed.cell.band) parts.push(feed.cell.band)
        return parts.join(" · ") + (stale ? i18n(" (stale)") : "")
    }

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 10
    compactRepresentation: CompactRep {}
    fullRepresentation: FullRep {}

    function metricValue(doc, name) {
        if (!doc || !doc.metrics) return null
        var v = doc.metrics[name]
        return (v === undefined) ? null : v
    }

    function handleOutput(stdout, exitCode) {
        if (exitCode !== 0 || !stdout || stdout.trim().length === 0) {
            stale = true
            return
        }
        var doc
        try {
            doc = JSON.parse(stdout)
        } catch (e) {
            stale = true
            return
        }
        if (!doc || doc.version !== 1) {
            stale = true
            return
        }
        feed = doc
        var ageSecs = (Date.now() / 1000) - doc.ts
        stale = ageSecs > pollInterval * 3
        var v = metricValue(doc, plasmoid.configuration.sparklineMetric)
        if (doc.state === "connected" && v !== null && !stale) {
            var h = history.slice()
            h.push(v)
            var max = Math.max(2, plasmoid.configuration.sparklineWindow)
            while (h.length > max) h.shift()
            history = h
        }
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            root.handleOutput(data.stdout, data["exit code"])
        }
    }

    Timer {
        interval: root.pollInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(plasmoid.configuration.feedCommand)
    }
}
```

- [ ] **Step 6: `install.sh`** (mode 0755)

```bash
#!/usr/bin/env bash
# Dev install: symlink package/ into the local plasmoid dir and refresh plasmashell.
set -euo pipefail
ID=com.github.thewrz.cellsignal
SRC="$(cd "$(dirname "$0")" && pwd)/package"
DST="$HOME/.local/share/plasma/plasmoids/$ID"
mkdir -p "$(dirname "$DST")"
[ -e "$DST" ] && rm -rf "$DST"
ln -s "$SRC" "$DST"
rm -rf "$HOME/.cache/plasmashell/qmlcache" 2>/dev/null || true
echo "linked $DST -> $SRC"
echo "test with: plasmoidviewer -a $ID   (or restart plasmashell: systemctl --user restart plasma-plasmashell)"
```

- [ ] **Step 7: Lint + commit**

Run: `qmllint package/contents/ui/main.qml || true` (module-import warnings are OK outside a Plasma env; syntax errors are not). Note: `CompactRep`/`FullRep` don't exist yet — create empty stubs so the package loads:

`package/contents/ui/CompactRep.qml` (stub, replaced in Task 5): `import QtQuick

Item {}` and `package/contents/ui/FullRep.qml` (stub, replaced in Task 6): `import QtQuick

Item {}`

```bash
git add package/ install.sh
git commit -m "feat: plasmoid skeleton — metadata, config schema, feed polling

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Compact representation (bars + sparkline + band)

**Files:**
- Create: `package/contents/ui/Bars.qml`, `package/contents/ui/Sparkline.qml`
- Replace: `package/contents/ui/CompactRep.qml`

**Interfaces:**
- Consumes: `root.feed`, `root.stale`, `root.history`, `root.connected`, `plasmoid.configuration.show*`.
- Produces: `Bars { rsrp: real|NaN }`, `Sparkline { samples: var }` — reused by FullRep in Task 6.

- [ ] **Step 1: `package/contents/ui/Bars.qml`**

```qml
import QtQuick
import org.kde.kirigami as Kirigami

// 4 stepped signal bars driven by RSRP. Theme-semantic colors:
// 4-3 bars positive, 2 neutral, 1-0 negative. NaN -> all empty.
Row {
    id: bars
    property real rsrp: NaN

    readonly property int level: {
        if (isNaN(rsrp)) return 0
        if (rsrp >= -90) return 4
        if (rsrp >= -100) return 3
        if (rsrp >= -110) return 2
        if (rsrp >= -120) return 1
        return 0
    }
    readonly property color levelColor: level >= 3 ? Kirigami.Theme.positiveTextColor
                                       : level === 2 ? Kirigami.Theme.neutralTextColor
                                       : Kirigami.Theme.negativeTextColor

    spacing: Math.max(1, Math.round(height / 12))

    Repeater {
        model: 4
        Rectangle {
            required property int index
            width: Math.max(2, Math.round(bars.height / 5))
            height: bars.height * (0.4 + 0.2 * index)
            anchors.bottom: parent.bottom
            radius: width / 3
            color: index < bars.level ? bars.levelColor : Kirigami.Theme.textColor
            opacity: index < bars.level ? 1.0 : 0.25
            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }
}
```

- [ ] **Step 2: `package/contents/ui/Sparkline.qml`**

```qml
import QtQuick
import org.kde.kirigami as Kirigami

// Scrolling history line of the configured metric. Auto-scales to the sample
// range (with a minimum span so noise doesn't fill the height). Theme accent.
Canvas {
    id: canvas
    property var samples: []
    property real minSpan: 10   // dB(m) — minimum vertical span

    onSamplesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
        target: Kirigami.Theme
        function onColorsChanged() { canvas.requestPaint() }
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!samples || samples.length < 2) return

        var lo = Math.min.apply(null, samples)
        var hi = Math.max.apply(null, samples)
        var mid = (lo + hi) / 2
        var span = Math.max(hi - lo, minSpan)
        lo = mid - span / 2
        hi = mid + span / 2

        var stepX = width / (samples.length - 1)
        var pad = Math.max(1, height * 0.1)
        function yFor(v) {
            return pad + (1 - (v - lo) / (hi - lo)) * (height - 2 * pad)
        }

        var accent = Kirigami.Theme.highlightColor
        ctx.beginPath()
        ctx.moveTo(0, yFor(samples[0]))
        for (var i = 1; i < samples.length; i++)
            ctx.lineTo(i * stepX, yFor(samples[i]))
        ctx.lineWidth = Math.max(1, height / 14)
        ctx.strokeStyle = accent
        ctx.stroke()

        // translucent fill under the line
        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.18)
        ctx.fill()
    }
}
```

- [ ] **Step 3: Replace `package/contents/ui/CompactRep.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    readonly property var feed: root.feed
    readonly property bool live: root.connected

    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: row.implicitHeight
    onClicked: root.expanded = !root.expanded

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        opacity: compact.live ? 1.0 : 0.5

        Bars {
            visible: plasmoid.configuration.showBars
            Layout.preferredHeight: Math.min(compact.height * 0.7, Kirigami.Units.gridUnit * 1.2)
            Layout.alignment: Qt.AlignVCenter
            rsrp: compact.live && feed.metrics.rsrp_dbm !== null ? feed.metrics.rsrp_dbm : NaN
        }

        Sparkline {
            visible: plasmoid.configuration.showSparkline
            samples: root.history
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
            Layout.preferredHeight: Math.min(compact.height * 0.8, Kirigami.Units.gridUnit * 1.4)
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter
            visible: plasmoid.configuration.showBand || plasmoid.configuration.showFrequency || plasmoid.configuration.showTech

            PlasmaComponents.Label {
                visible: plasmoid.configuration.showBand
                text: compact.live && feed.cell.band ? feed.cell.band : "—"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: true
            }
            PlasmaComponents.Label {
                visible: plasmoid.configuration.showFrequency && compact.live && feed.cell.freq_mhz !== null
                text: compact.live && feed.cell.freq_mhz !== null ? feed.cell.freq_mhz + " MHz" : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                opacity: 0.7
            }
            PlasmaComponents.Label {
                visible: plasmoid.configuration.showTech && compact.live && feed.tech
                text: compact.live && feed.tech ? feed.tech.toUpperCase() : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                opacity: 0.7
            }
        }
    }
}
```

- [ ] **Step 4: Visual test against fixtures**

```bash
./install.sh
plasmoidviewer -a com.github.thewrz.cellsignal &
# In widget settings (right-click → Configure), set feed command to:
#   cat /home/adam/github/plasma-applet-cellsignal/fixtures/connected-lte.json
```
Expected: bars=3 green-ish (theme positive), band "B12", sparkline appears after ~2 polls (flat line — fixture is static). Swap to `weak-signal.json` → 1 bar, negative color. `disconnected.json` → dimmed, "—".

- [ ] **Step 5: Commit** — `git add package/contents/ui/ && git commit -m "feat: compact representation — bars, live sparkline, band labels" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"`

---

### Task 6: Full representation (popup)

**Files:**
- Create: `package/contents/ui/MetricRow.qml`
- Replace: `package/contents/ui/FullRep.qml`

**Interfaces:**
- Consumes: `root.feed`, `root.stale`, `root.history`, `Bars`, `Sparkline`, `plasmoid.configuration.showRsrp/Rsrq/Snr/Rssi`.

- [ ] **Step 1: `package/contents/ui/MetricRow.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One metric line: name, value+unit, level bar normalized to [rangeLo, rangeHi].
RowLayout {
    id: metricRow
    property string label
    property var value: null      // number or null
    property string unit
    property real rangeLo
    property real rangeHi
    property int decimals: 1

    readonly property real norm: value === null ? 0
        : Math.max(0, Math.min(1, (value - rangeLo) / (rangeHi - rangeLo)))

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    PlasmaComponents.Label {
        text: metricRow.label
        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
        opacity: 0.7
    }
    PlasmaComponents.Label {
        text: metricRow.value === null ? "—"
              : metricRow.value.toFixed(metricRow.decimals) + " " + metricRow.unit
        font.family: "monospace"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5
        horizontalAlignment: Text.AlignRight
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit / 3)
        radius: height / 2
        color: Kirigami.Theme.textColor
        opacity: 0.15
        Rectangle {
            width: parent.width * metricRow.norm
            height: parent.height
            radius: height / 2
            color: metricRow.norm > 0.55 ? Kirigami.Theme.positiveTextColor
                 : metricRow.norm > 0.3 ? Kirigami.Theme.neutralTextColor
                 : Kirigami.Theme.negativeTextColor
            opacity: metricRow.value === null ? 0 : 1
            Behavior on width { NumberAnimation { duration: 250 } }
        }
    }
}
```

Note: outer track opacity 0.15 also dims the fill child — set the track color with alpha instead if that shows: `color: Qt.alpha(Kirigami.Theme.textColor, 0.15)` and `opacity: 1`. Use the `Qt.alpha` form.

- [ ] **Step 2: Replace `package/contents/ui/FullRep.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full
    readonly property var feed: root.feed
    readonly property bool live: root.connected

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    spacing: Kirigami.Units.smallSpacing

    PlasmaExtras.PlaceholderMessage {
        visible: !full.live
        Layout.fillWidth: true
        Layout.fillHeight: true
        iconName: "network-mobile-off"
        text: !feed ? i18n("No feed") : root.stale ? i18n("Feed is stale") : feed.state
        explanation: i18n("Check the feeder service and the feed command in settings.")
    }

    ColumnLayout {
        visible: full.live
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Bars {
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                rsrp: full.live && feed.metrics.rsrp_dbm !== null ? feed.metrics.rsrp_dbm : NaN
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: {
                    if (!full.live) return ""
                    var parts = []
                    if (feed.cell.band) parts.push(feed.cell.band)
                    if (feed.cell.freq_mhz !== null) parts.push(feed.cell.freq_mhz + " MHz")
                    if (feed.tech) parts.push(feed.tech.toUpperCase())
                    return parts.join(" · ")
                }
                font.bold: true
            }
        }

        MetricRow {
            visible: plasmoid.configuration.showRsrp
            label: "RSRP"; unit: "dBm"; rangeLo: -125; rangeHi: -75; decimals: 0
            value: full.live ? feed.metrics.rsrp_dbm : null
        }
        MetricRow {
            visible: plasmoid.configuration.showRsrq
            label: "RSRQ"; unit: "dB"; rangeLo: -20; rangeHi: -3
            value: full.live ? feed.metrics.rsrq_db : null
        }
        MetricRow {
            visible: plasmoid.configuration.showSnr
            label: "SNR"; unit: "dB"; rangeLo: -10; rangeHi: 30
            value: full.live ? feed.metrics.snr_db : null
        }
        MetricRow {
            visible: plasmoid.configuration.showRssi
            label: "RSSI"; unit: "dBm"; rangeLo: -110; rangeHi: -50; decimals: 0
            value: full.live ? feed.metrics.rssi_dbm : null
        }

        Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }

        PlasmaComponents.Label {
            text: i18n("History (%1)", plasmoid.configuration.sparklineMetric.split("_")[0].toUpperCase())
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
        }
        Sparkline {
            samples: root.history
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        }
    }

    Item { Layout.fillHeight: true; visible: full.live }
}
```

- [ ] **Step 3: Visual test** — `plasmoidviewer -a com.github.thewrz.cellsignal`, click the compact rep; check all fixture states (connected → rows + bars + history; disconnected → placeholder). Toggle each `show*` in settings and confirm rows hide.

- [ ] **Step 4: Commit** — `git add package/contents/ui/ && git commit -m "feat: popup with metric rows, level bars, history graph" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"`

---

### Task 7: Config page + README + build script

**Files:**
- Create: `package/contents/ui/configGeneral.qml`, `build.sh`, `README.md`

- [ ] **Step 1: `package/contents/ui/configGeneral.qml`**

```qml
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_feedCommand: feedCommand.text
    property alias cfg_pollInterval: pollInterval.value
    property alias cfg_showBars: showBars.checked
    property alias cfg_showSparkline: showSparkline.checked
    property alias cfg_showBand: showBand.checked
    property alias cfg_showFrequency: showFrequency.checked
    property alias cfg_showTech: showTech.checked
    property alias cfg_showRsrp: showRsrp.checked
    property alias cfg_showRsrq: showRsrq.checked
    property alias cfg_showSnr: showSnr.checked
    property alias cfg_showRssi: showRssi.checked
    property alias cfg_sparklineWindow: sparklineWindow.value
    property string cfg_sparklineMetric
    onCfg_sparklineMetricChanged: {
        sparklineMetric.currentIndex = sparklineMetric.indexOfValue(cfg_sparklineMetric)
    }

    QQC2.TextField {
        id: feedCommand
        Kirigami.FormData.label: i18n("Feed command:")
        Layout.fillWidth: true
    }
    QQC2.SpinBox {
        id: pollInterval
        Kirigami.FormData.label: i18n("Poll interval (s):")
        from: 1; to: 30
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Panel") }
    QQC2.CheckBox { id: showBars; text: i18n("Signal bars") }
    QQC2.CheckBox { id: showSparkline; text: i18n("Live sparkline") }
    QQC2.CheckBox { id: showBand; text: i18n("Band (e.g. B12)") }
    QQC2.CheckBox { id: showFrequency; text: i18n("Frequency (MHz)") }
    QQC2.CheckBox { id: showTech; text: i18n("Technology (LTE/5G)") }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Metrics (popup)") }
    QQC2.CheckBox { id: showRsrp; text: "RSRP" }
    QQC2.CheckBox { id: showRsrq; text: "RSRQ" }
    QQC2.CheckBox { id: showSnr; text: "SNR" }
    QQC2.CheckBox { id: showRssi; text: "RSSI" }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Sparkline") }
    QQC2.ComboBox {
        id: sparklineMetric
        Kirigami.FormData.label: i18n("Metric:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: "RSRP", value: "rsrp_dbm" },
            { text: "RSRQ", value: "rsrq_db" },
            { text: "SNR", value: "snr_db" }
        ]
        onActivated: page.cfg_sparklineMetric = currentValue
    }
    QQC2.SpinBox {
        id: sparklineWindow
        Kirigami.FormData.label: i18n("History (samples):")
        from: 10; to: 600
    }
}
```

- [ ] **Step 2: `build.sh`** (mode 0755)

```bash
#!/usr/bin/env bash
# Build a store-uploadable .plasmoid (zip of package/ contents).
set -euo pipefail
cd "$(dirname "$0")"
VER=$(python3 -c "import json; print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
mkdir -p dist
OUT="dist/cellsignal-v${VER}.plasmoid"
rm -f "$OUT"
(cd package && zip -qr "../$OUT" .)
echo "built $OUT"
```

- [ ] **Step 3: `README.md`**

```markdown
# Cell Signal

KDE Plasma 6 widget that displays cellular modem signal metrics in the panel:
signal bars, a scrolling history sparkline, RSRP, RSRQ, SNR, band, and
frequency. Colors follow the Plasma theme in light and dark mode.

The widget does not talk to modems directly. It reads a JSON document
(see [docs/CONTRACT.md](docs/CONTRACT.md)) written by a separate feeder
script, so support for a modem means writing a feeder for it.

Included feeders:

| Feeder | Hardware |
|---|---|
| [feeders/xmm7360](feeders/xmm7360/) | Intel XMM7360 (iosm kernel driver + xmm7360-pci userspace) |
| feeders/mmcli | ModemManager modems (planned) |

## Install the widget

    ./install.sh          # dev symlink into ~/.local/share/plasma/plasmoids
    # or: kpackagetool6 -t Plasma/Applet -i package/

Add "Cell Signal" from the panel's Add Widgets dialog, then set up a feeder
(see the feeder's README).

## Configuration

Bars, sparkline, band, frequency, technology label, and each metric can be
shown or hidden individually. Poll interval is 1 to 30 seconds. The feed
command is a setting, so any command that prints contract JSON works.

## Privacy

The feed contract contains signal metrics only. It has no fields for IMEI,
ICCID, IMSI, or cell identifiers.

## License

MIT.
```

- [ ] **Step 4: Full visual pass, lint, commit, PR**

```bash
qmllint package/contents/ui/*.qml || true   # syntax must be clean
./install.sh && plasmoidviewer -a com.github.thewrz.cellsignal
# verify: config page opens, every toggle works, feed command editable
git add package/ build.sh README.md
git commit -m "feat: config page, build script, README

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push -u origin feat/plasmoid-mvp
gh pr create --draft --title "feat: plasmoid MVP — sparkline panel, metrics popup, config" --body "## Why
The widget itself — phase 1 of the spec.

## What
Pure-QML Plasma 6 plasmoid: compact rep (bars + live sparkline + band), popup (metric rows + history), full config page, dev install + store build scripts.

## Testing
- [ ] qmllint clean
- [ ] plasmoidviewer against all 5 fixtures (states render correctly)
- [ ] all config toggles verified
- [ ] dogfood on wrz-p52 panel with live feeder

🤖 Co-authored by Claude Fable 5. Closes #2."
```

---

### Task 8: Dogfood on wrz-p52 (no PR — deployment)

**Files:** none in repo (host deployment)

- [ ] **Step 1: Install feeder** (Adam runs; needs sudo)

```bash
cd ~/github/plasma-applet-cellsignal/feeders/xmm7360
sudo install -Dm755 cellsignal-feeder-xmm7360 /usr/local/bin/cellsignal-feeder-xmm7360
sudo install -Dm755 xmm7360_decode.py /usr/local/bin/xmm7360_decode.py
sudo install -Dm644 cellsignal-xmm7360.service /etc/systemd/system/cellsignal-xmm7360.service
sudo install -Dm644 cellsignal-xmm7360.timer /etc/systemd/system/cellsignal-xmm7360.timer
sudo systemctl daemon-reload && sudo systemctl enable --now cellsignal-xmm7360.timer
sleep 3 && cat /run/cellsignal.json
```
Expected: contract JSON with live RSRP/band. Note: the old `lte-signal.timer` keeps running (separate file, no conflict — both flock `/run/lte.lock`, so ticks serialize; disable `lte-signal.timer` once the widget replaces the Command Output setup).

- [ ] **Step 2: Add widget to panel** — `./install.sh`, restart plasmashell (`systemctl --user restart plasma-plasmashell`), Add Widgets → "Cell Signal". Default feed command already points at `/run/cellsignal.json`.

- [ ] **Step 3: Verify end-to-end**
- Panel shows bars + moving sparkline (values change tick to tick) + `B12`/`B2`.
- Click → popup rows match `cat /run/cellsignal.json`.
- `sudo systemctl stop cellsignal-xmm7360.timer` → widget dims to stale within ~3 polls; restart → recovers.
- Light/dark theme switch → colors follow.

- [ ] **Step 4: Mark PRs ready + merge** (after review), move issues to Done.

---

## Self-review notes

- Spec coverage: contract (T1), feeder (T2–3), widget compact/full/config (T4–7), install/build (T4/T7), dogfood (T8). mmcli feeder + store upload are phase 2 by design.
- Type consistency: `feed.metrics.rsrp_dbm` naming matches contract and fixtures throughout; `Bars.rsrp` takes NaN sentinel; `Sparkline.samples` array of numbers.
- No placeholders: every file's full content is in its task.
