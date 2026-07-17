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
