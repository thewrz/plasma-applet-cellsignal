# Cell Signal feed contract — v2

A feeder publishes ONE JSON document (typically to `/run/cellsignal.json`,
world-readable). The widget executes a configurable command (default
`cat /run/cellsignal.json`) and parses stdout. This document is normative.

## Versioning

The current version is `2`. Version 2 is **additive over version 1**: every v2
field beyond the v1 set is nullable, and no v1 field changed position or
meaning. A valid v1 document is still accepted — consumers read `version` and
treat any field absent for that version as `null`. Feeders that only produce
the v1 fields may keep emitting `version: 1`.

## Document (v1 core)

| Key | Type | Meaning |
|---|---|---|
| `version` | int | Contract version (`1` or `2`). |
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

## Document (v2 additions)

All nullable; a feeder that cannot measure a field emits `null` (or `[]` for
`neighbors`). Every source below was validated on the XMM7360 hardware drill
(issue #15); other feeders may leave these `null` until they have equivalents.

| Key | Type | Source & meaning |
|---|---|---|
| `cell.bandwidth_mhz` | number\|null | Serving (PCell) downlink channel bandwidth in MHz, from `AT+GTCAINFO?` dl_bw code (`0`→1.4, `1`→3, `2`→5, `3`→10, `4`→15, `5`→20). |
| `cell.timing_advance` | int\|null | Serving-cell Timing-Advance from `AT+XMCI=1` (type-4 line, field 12 hex). `null` when `0x7FFFFFFF` (N/A) or `0` (idle). |
| `cell.distance_m` | int\|null | Line-of-sight distance to the serving tower, `round(timing_advance × 78.125)` metres, when TA is valid and `> 0`. Radio path (≈78 m granularity), not road distance. |
| `cell.rrc_state` | `"connected"`\|`"idle"`\|null | RRC connection state from `AT+CSCON?` (`,1`→connected, `,0`→idle). |
| `aggregation` | object\|null | Carrier-aggregation summary from `AT+GTCAINFO?`, or `null` when unknown. `carriers` (int) = component-carrier count; `bands` (string[]) = per-carrier band labels; `aggregate_mhz` (number\|null) = sum of the carriers' downlink bandwidths. |
| `neighbors` | array | Detected neighbour cells from `AT+XMCI=1` type-5 lines: each `{band: string\|null, earfcn: int, rsrp_dbm: number\|null, rsrq_db: number\|null}`. `[]` when none detected. |
| `operator` | string\|null | Registered network operator name from `AT+COPS?` (alphanumeric formats only). Changes rarely, so a feeder may cache it across ticks rather than re-query every tick. Numeric-only PLMN responses yield `null`. |

Rules:
- Unknown values are `null` — never fabricated.
- Extra keys are allowed; consumers MUST ignore unknown keys (forward compatibility).
- **Privacy:** the contract has no fields for device or subscriber identifiers
  (IMEI/ICCID/IMSI) and none may be added. Cell identifiers (cell-ID/TAC/PCI) are
  excluded from every version; the v2 sources above carry them in their raw AT
  responses (TAC/CID in `GTCAINFO`/`XMCI`, PCI in both), and feeders parse past
  them — they are never emitted. Timing-Advance, distance and neighbour
  measurements are RF measurements, not identifiers, and are publishable.

## Writing a feeder

Emit the document atomically (write temp file, `rename()`), any cadence ≥1s.
Run with the least privilege your hardware allows. See `feeders/` for examples.
