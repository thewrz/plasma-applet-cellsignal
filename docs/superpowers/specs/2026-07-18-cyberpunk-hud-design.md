# Cell Signal — Cyberpunk HUD redesign

**Date:** 2026-07-18 · **Status:** approved

## Context

Hardware drilling (issue #15) proved the XMM7360 exposes far more than the MVP shows:
timing-advance → distance-to-tower, carrier aggregation, neighbor cells, channel
bandwidth, RRC state. The MVP popup is a plain metric list. This redesign turns the
widget into a committed "cyberpunk HUD" — an always-dark neon cockpit panel whose accent
color reacts to signal quality — that surfaces all of that data. Panel and popup both get
the treatment; the popup is the dense two-column dashboard ("Layout B" from the approved
mockup).

Delivered in two sequential PRs (data first, then look) so every field is real on the day
the new UI ships.

- **Repo:** `thewrz/plasma-applet-cellsignal`
- **Depends on:** issue #15 hardware findings (AT+XMCI / +GTCAINFO / +CSCON decodes)

## Design decisions (locked)

- **Aesthetic:** cyberpunk HUD — always-dark translucent panel, faint grid, clipped
  ("chamfered") corners, glow. **Ignores the desktop light/dark theme by choice** (a
  deliberately single-look element, the allowed exception to theme-adaptivity).
- **Accent:** *signal-reactive* — the whole HUD re-tints with quality: cyan-green (good) →
  amber (fair) → magenta (weak), with a smooth color transition on change.
- **Motion:** lively but tasteful — easing bars, scrolling sparkline, accent re-tint,
  pulsing RRC dot + range rings. All gated on the platform reduced-animation setting.
- **Scope:** both the compact representation (panel) and full representation (popup) go
  cyberpunk. Popup uses the two-column dashboard layout.

---

## PR 1 — Contract v2 + feeder

### Contract v2 (`docs/CONTRACT.md`)

Bump `version` to `2`. All additions are **nullable and additive** — a v1 document still
validates; existing fields keep their positions and meanings. New fields:

```json
{
  "version": 2,
  "ts": 1789000000,
  "state": "connected",
  "tech": "lte",
  "metrics": { "rsrp_dbm": -95.0, "rsrq_db": -12.0, "snr_db": 5.0, "rssi_dbm": null },
  "cell": {
    "band": "B12", "earfcn": 5110, "freq_mhz": 700,
    "bandwidth_mhz": 10,
    "timing_advance": 28,
    "distance_m": 2188,
    "rrc_state": "connected"
  },
  "aggregation": { "carriers": 2, "bands": ["B12", "B2"], "aggregate_mhz": 30 },
  "neighbors": [
    { "band": "B2", "earfcn": 700, "rsrp_dbm": -105.0, "rsrq_db": -15.0 }
  ],
  "operator": "MOBILE",
  "quality_pct": 61,
  "source": "xmm7360"
}
```

| New field | Type | Source |
|---|---|---|
| `cell.bandwidth_mhz` | int\|null | GTCAINFO PCell dl_bw code (0→1.4,1→3,2→5,3→10,4→15,5→20) |
| `cell.timing_advance` | int\|null | XMCI serving line (type 4/5) field 12 hex; null when `0x7FFFFFFF`/absent |
| `cell.distance_m` | int\|null | `round(timing_advance × 78.125)` when TA valid & > 0 |
| `cell.rrc_state` | `"connected"`\|`"idle"`\|null | AT+CSCON? — `,1`→connected, `,0`→idle |
| `aggregation` | object\|null | GTCAINFO: leading count + per-carrier band; `aggregate_mhz` = sum of carrier bandwidths |
| `neighbors` | array | XMCI type-5 lines → `{band, earfcn, rsrp_dbm, rsrq_db}`; `[]` when none |
| `operator` | string\|null | AT+COPS? operator name; changes rarely, so the feeder may cache it across ticks rather than re-query every tick |

**Privacy unchanged:** TA/distance/neighbor measurements are publishable; TAC/CID/PCI are
parsed past and never emitted. No IMEI/ICCID/IMSI. Fixtures use synthetic values.

### Feeder v2 (`feeders/xmm7360/`)

Per tick the feeder now issues three safe read commands (all validated in the #15 drills,
no wedge risk): `AT+XMCI=1` (serving trio + EARFCN + TA + type-5 neighbors), `AT+GTCAINFO?`
(carrier count + per-carrier band/bandwidth), `AT+CSCON?` (RRC). Decode functions live in
`xmm7360_decode.py` with pytest coverage against captured-shape fixtures (synthetic ids):

- `parse_xmci(text)` extends to also return `timing_advance` and a `neighbors` list.
- `parse_gtcainfo(text)` → `{carriers, bands, aggregate_mhz, serving_bandwidth_mhz}`.
- `parse_cscon(text)` → `"connected"|"idle"|None`.
- `distance_m(ta)` → `round(ta × 78.125)` or None.

The widget accepts `version` 1 **or** 2; any absent field is treated as null.

---

## PR 2 — Cyberpunk widget (panel + popup)

### Shared HUD core (`package/contents/ui/hud/`)

- **`HudStyle.qml`** (singleton/shared): the **signal-reactive color engine** — a function
  mapping `quality_pct` (fallback RSRP) → accent:
  - good (`quality ≥ 55` / RSRP ≥ −95): cyan-green `#29e7cd`
  - fair (`30 ≤ quality < 55`): amber `#ffb020`
  - weak (`quality < 30`): magenta `#ff3b8b`
  Plus style tokens: mono font stack, dark grounds, glow strengths, chamfer size. Exposes
  `accentColor`; a config option can pin a fixed accent instead of reactive.
- **`HudFrame.qml`**: reusable clipped-corner dark panel shell (grid background, glow
  border) wrapping any content — used by both panel and popup.

`root.accentColor` (in `main.qml`) binds to `HudStyle`; both representations consume it, so
the whole widget re-tints together via one `Behavior on color { ColorAnimation }`.

### Panel (compact representation)

Restyle `CompactRep.qml` + `Bars.qml` + `Sparkline.qml`: dark mini-strip via `HudFrame`,
mono text, glowing bars, neon band label, glow-endpoint sparkline. Elements stay
individually toggleable (existing config). Sized to panel height.

### Popup (full representation) — Layout B

Rebuild `FullRep.qml` as the two-column dashboard inside `HudFrame`:

- **Title row:** widget name + RRC dot (pulsing when connected) + operator/tech.
- **Left column:** `MetricBar` rows (RSRP/RSRQ/SNR/quality, animated fill), the history
  `Sparkline`, and the `TowerModule` (distance-to-tower with pulsing range rings).
- **Right column:** `KvRow` stack — band, frequency, bandwidth, EARFCN, aggregation
  (bands + aggregate MHz), then `NeighborList` (band + RSRP chips).
- Any null field dims/hides; disconnected/stale renders the frame with a status line.

New sub-components (many small files): `MetricBar.qml`, `KvRow.qml`, `TowerModule.qml`,
`NeighborList.qml`.

### Config

Existing toggles retained. New: show aggregation / neighbors / distance / bandwidth / RRC;
glow-intensity control; signal-reactive-vs-fixed-accent switch. KConfigXT entries +
`configGeneral.qml` controls.

### Motion

Bar-width easing, sparkline scroll, accent `ColorAnimation`, RRC-dot + range-ring pulses.
All animations bound to the platform reduced-animation flag (Kirigami/Plasma) so they stop
when the user disables animations.

---

## Testing & verification

- Feeder decode: pytest on `parse_xmci`/`parse_gtcainfo`/`parse_cscon`/`distance_m` against
  captured-shape fixtures (synthetic identifiers). Contract fixtures gain v2 examples;
  privacy pinning tests extend to the new fields.
- Widget: qmllint clean; `plasmoidviewer` against v2 fixtures (connected / partial /
  disconnected / CA-active); every config toggle verified; visual pass on wrz-p52's panel.
- End-to-end: real feeder v2 → live HUD showing distance-to-tower, CA, neighbors.

## Out of scope

GPS/location (dead — no antenna, issues #12–14 closed), the mmcli feeder (#16) emitting v2
fields (mmcli lands v1; v2 fields are xmm7360-only until MM equivalents are wired), 5G NR.

## Phasing

1. **PR 1:** contract v2 + feeder v2 + tests. Feed carries the new fields; widget unchanged
   (ignores them).
2. **PR 2:** cyberpunk panel + popup consuming v2. Everything real on arrival.
