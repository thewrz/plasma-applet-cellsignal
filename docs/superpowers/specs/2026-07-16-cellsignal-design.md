# Cell Signal — design spec

**Date:** 2026-07-16 · **Status:** approved

## Context

No desktop widget on any Linux platform displays real cellular signal metrics — KDE's
plasma-nm and every GNOME extension top out at a 0–100 % bar. Meanwhile modems expose
RSRP/RSRQ/SNR (ModemManager DBus) or richer (Intel XMM7360 RPC, decoded by this
project's author). Cell Signal is a KDE Plasma 6 plasmoid that fills that gap: an
eye-catching, theme-native, configurable live readout of cellular signal quality,
modem-agnostic by design.

- **Repo:** `thewrz/plasma-applet-cellsignal` (public, GitHub; name verified unclaimed)
- **Plasmoid Id:** `com.github.thewrz.cellsignal` · **Display name:** Cell Signal
- **License:** MIT (no code lifted from GPL references; everything written fresh)

## Architecture

Three decoupled pieces; the JSON contract is the only coupling:

```
plasmoid (pure QML) --executes every N s--> feed command --reads--> /run/cellsignal.json
                                                                 ^
                                             feeder daemon/timer (per-modem) writes it
```

- **Plasmoid** — pure QML (`PlasmoidItem` root; org.kde.plasma.plasmoid, plasma.components,
  kirigami, plasma5support). No C++, no build step, store.kde.org-eligible. Polls via
  QML `Timer` + `Plasma5Support.DataSource` engine `"executable"` running a configurable
  feed command (default `cat /run/cellsignal.json`), parses stdout as JSON.
- **Feeders** — per-modem producers of contract JSON, shipped in-repo:
  - `feeders/xmm7360/` — Intel XMM7360 via the xmm7360-pci RPC channel (this project's
    own decode: enable radio-signal reporting → catch `UtaMsNetRadioSignalIndCb` →
    disable; field map validated across bands B2/B12). systemd service+timer, default 2 s
    (one RPC session ≈ 1 s, so 2 s is the tick floor). Includes port-clog hardening
    (drain-first, SIGTERM-safe disable, journal logging).
  - `feeders/mmcli/` — the universal backend: `mmcli --signal-setup=<rate>` +
    `--signal-get` (rsrp/rsrq/snr) + cell info (earfcn → band/frequency derived from a
    band table). Makes the widget work for standard QMI/MBIM modems out of the box.
- Anyone adapts a new modem by writing a feeder; the widget never changes.

## JSON contract (v1 — `docs/CONTRACT.md` is normative)

```json
{
  "version": 1,
  "ts": 1789000000,
  "state": "connected",
  "tech": "lte",
  "metrics": { "rsrp_dbm": -95.0, "rsrq_db": -9.8, "snr_db": 16.5, "rssi_dbm": null },
  "cell": { "band": "B12", "earfcn": 5110, "freq_mhz": 700 },
  "quality_pct": 62,
  "source": "xmm7360"
}
```

- `state`: `connected | disconnected | no-modem | error` (widget renders non-connected
  states dimmed with a status line, never stale numbers; also dims when `ts` is older
  than 3 poll intervals).
- Unknown metrics are `null`, never fabricated. Extra keys are allowed (forward-compat);
  consumers ignore what they don't know.
- **Privacy is contract law:** the schema has no fields for IMEI/ICCID/IMSI. Cell
  identifiers (cell-ID/TAC/PCI — coarse location) are excluded from v1; any future
  addition is opt-in and requires a version bump. Fixtures use synthetic values only.

## Widget UI (visual direction: live sparkline panel)

**Compact representation (panel):** horizontally arranged, every element toggleable —
1. Quality bars: 4 stepped Rectangles filled by RSRP thresholds
   (≥−90 → 4, ≥−100 → 3, ≥−110 → 2, ≥−120 → 1), colored via `Kirigami.Theme`
   semantic colors: positive (4–3 bars), neutral (2), negative (1–0).
2. Live sparkline: `Canvas` drawing a ring buffer of the last N samples (default RSRP,
   ~2 min window), line in `Kirigami.Theme.highlightColor`, subtle fill. Repaints per
   poll — motion visible in the panel.
3. Band label (e.g. `B12`) in `Kirigami.Theme.textColor` at small size.

**Full representation (popup):** metric rows (label, value+unit, horizontal level bar
normalized to each metric's real range: RSRP −140…−44, RSRQ −20…−3, SNR −10…+30);
larger history graph of the sparkline buffer; cell line `B12 · 700 MHz · LTE`; a
"stale/disconnected" banner state.

**Theme:** zero hardcoded colors; everything through `Kirigami.Theme` so light/dark and
accent-color changes are automatic.

## Configuration (KConfigXT `main.xml` + `Kirigami.FormLayout` page)

| Entry | Type | Default |
|---|---|---|
| showBars / showSparkline / showBand / showFrequency / showTech | Bool | true/true/true/false/false |
| showRsrp / showRsrq / showSnr / showRssi (popup + optional panel text) | Bool | true/true/true/false |
| pollInterval (seconds, 1–30) | Int | 2 |
| feedCommand | String | `cat /run/cellsignal.json` |
| sparklineMetric (rsrp/rsrq/snr) | String | rsrp |
| sparklineWindow (samples) | Int | 60 |

## Security & privacy

- Feed pipeline carries metrics only; feeders never publish device or subscriber
  identifiers. The repo (docs, fixtures, tests, commit history) must never contain a
  real IMEI/ICCID — synthetic values only.
- Feeders run as root only where the hardware demands it (xmm7360 RPC node); the
  published JSON is world-readable and safe by construction.
- Widget executes only the user-configured feed command (same trust model as KDE's
  Command Output widget).

## Testing & verification

- Feeder decode logic: pytest with recorded-structure fixtures (synthetic values).
- Widget: developed against `fixtures/*.json` via `cat` as the feed command —
  no modem needed; `plasmoidviewer` / `plasmawindowed` for the dev loop;
  `install.sh` symlinks `package/` into `~/.local/share/plasma/plasmoids/`.
- CI: qmllint, shellcheck, pytest.
- End-to-end: real xmm7360 feeder on wrz-p52's panel (dogfood).

## Repo layout

```
plasma-applet-cellsignal/
├── package/                  # the plasmoid (metadata.json, contents/{ui,config})
├── feeders/{xmm7360,mmcli}/  # feeder + systemd units + per-feeder README
├── docs/CONTRACT.md          # JSON schema v1 (the public interface)
├── fixtures/                 # synthetic contract JSONs
├── install.sh / build.sh     # dev symlink / zip → dist/*.plasmoid
└── README.md, LICENSE (MIT)
```

## Phasing

1. **MVP (dogfood):** contract + xmm7360 feeder + widget (sparkline panel, popup,
   config) working on wrz-p52.
2. **Universal:** mmcli feeder, polish, `.plasmoid` build, store.kde.org listing.
3. **Live mode:** persistent streaming feeder (reporting left enabled, ~1 s updates) —
   gated on an empirical probe of the modem's indication rate and lock coordination
   with the `lte` wrapper.

## Out of scope (v1)

5G NR field decode for xmm7360 (LTE only), neighbor-cell display, cell identifiers,
Waybar/GNOME ports, historical persistence beyond the in-memory ring buffer.
