# mmcli (ModemManager) feeder

This feeder publishes radio measurements for the Cell Signal Plasma widget from
any modem [ModemManager](https://modemmanager.org/) manages (QMI, MBIM, or AT).
It does no custom modem decode: it reads ModemManager's own measurements through
`mmcli --output-json` and reshapes them into the feed contract.

It runs as a systemd **user** service and writes the feed to your user runtime
directory, so installing and running it needs no sudo. The one exception is
noted under *Requirements*.

## Status

The feeder emits [contract v2](../../docs/CONTRACT.md). Its parsers and document
builder are covered by captured-shape fixtures with synthetic identifiers. A
full manual pass against a live ModemManager modem — installed, feeding the
Plasma HUD — remains the outstanding acceptance step.

## Requirements

- ModemManager with `mmcli`; version **1.20 or newer** for `--get-cell-info`
  (band, frequency, and neighbour data). Older ModemManager still supplies the
  signal metrics; the cell fields stay null.
- a modem ModemManager manages and reports as `connected`
- Python 3 and a systemd user instance
- an active local login session. ModemManager grants the active session the
  `org.freedesktop.ModemManager1.Device.Control` polkit action
  (`allow_active=yes` in the upstream policy), which is what `--signal-setup`
  needs, so no password prompt appears. A distribution that overrides that
  policy to require admin authentication is the one case where enabling signal
  polling may prompt; install a polkit rule granting your user that action, or
  run `mmcli -m <i> --signal-setup=<rate>` once yourself, to clear it.

The built-in EARFCN table labels the LTE bands B2, B4, B5, B12, B14, B17, B29,
B30, B66, and B71 (see [`../shared/cellsignal_bands.py`](../shared/cellsignal_bands.py)).
Other EARFCNs still carry measurements, but their band and nominal frequency are
reported as unknown until the table is extended. 5G NR serving cells report an
NR-ARFCN rather than an LTE EARFCN, so their band and frequency stay null.

## Published data

Each successful connected sample can include:

| Data | ModemManager source |
|---|---|
| RSRP, RSRQ, SNR, RSSI (already in dBm/dB) | `mmcli --signal-get` |
| Serving EARFCN → band and frequency, neighbour cells | `mmcli --get-cell-info` |
| State, access technology, operator name | `mmcli -m <i>` |

ModemManager's signal and cell-info interfaces do not expose channel bandwidth,
timing advance, RRC state, or carrier aggregation, so those v2 fields are always
null from this feeder.

## Install or upgrade

Run these from `feeders/mmcli/` — no sudo:

```sh
systemctl --user stop cellsignal-mmcli.timer cellsignal-mmcli.service 2>/dev/null || true
install -Dm755 cellsignal-feeder-mmcli ~/.local/bin/cellsignal-feeder-mmcli
install -Dm644 ../shared/cellsignal_bands.py ~/.local/bin/cellsignal_bands.py
install -Dm644 mmcli_parse.py ~/.local/bin/mmcli_parse.py
install -Dm644 cellsignal-mmcli.service ~/.config/systemd/user/cellsignal-mmcli.service
install -Dm644 cellsignal-mmcli.timer ~/.config/systemd/user/cellsignal-mmcli.timer
systemctl --user daemon-reload
systemctl --user enable --now cellsignal-mmcli.timer
```

The three Python files (`cellsignal-feeder-mmcli`, `mmcli_parse.py`,
`cellsignal_bands.py`) import each other and must be installed together.

Run one sample immediately and inspect the result:

```sh
systemctl --user start --wait cellsignal-mmcli.service
python3 -m json.tool "$XDG_RUNTIME_DIR/cellsignal.json"
systemctl --user status cellsignal-mmcli.timer
```

A connected feed starts with `"version": 2`. The timer runs every five seconds
after an initial 30-second delay.

The service runs within your login session (it is not enabled to linger). That
matches the polkit `allow_active` grant above: outside an active session,
ModemManager access would prompt, so the feed is meant to run while you are
logged in.

## Point the widget at the feed

This feeder writes to `$XDG_RUNTIME_DIR/cellsignal.json`, not the widget's
default `/run/cellsignal.json`. In the widget settings, set the feed command to
your resolved runtime path, for example:

```sh
cat /run/user/1000/cellsignal.json
```

Replace `1000` with your own UID (`id -u`). If your Plasma build runs the feed
command through a shell, `cat $XDG_RUNTIME_DIR/cellsignal.json` also works; the
literal path is the reliable form.

## Choosing a poll rate

`CELLSIGNAL_MMCLI_RATE` (default `5`, seconds) is the rate handed to
ModemManager's `--signal-setup`; it is how often the modem refreshes its signal
measurements. Keep it at or below the timer's `OnUnitActiveSec` so each tick
reads a freshly polled sample. To change both together, edit
`OnUnitActiveSec=` in `cellsignal-mmcli.timer` and add the env var to the
service, for example with a drop-in:

```sh
systemctl --user edit cellsignal-mmcli.service
# [Service]
# Environment=CELLSIGNAL_MMCLI_RATE=2
```

A faster rate costs more radio wakeups for little benefit; 2–10 seconds is a
reasonable range.

## One feeder owns the feed file

Run only one feeder for a given feed file. This feeder writes
`$XDG_RUNTIME_DIR/cellsignal.json` (per-user); the xmm7360 feeder writes
`/run/cellsignal.json` (system-wide). The default paths differ, so the two do
not collide, but the widget reads one file — point it at whichever feeder you
run, and do not run two feeders writing the same path.

## Direct diagnostics

These modes run one sample without touching the timer:

```sh
cellsignal-feeder-mmcli --print
cellsignal-feeder-mmcli --debug
```

`--print` writes the contract document to stdout. `--debug` also prints each
`mmcli` invocation and its raw output to stderr; review that before sharing it,
because raw `--get-cell-info` output contains cell identifiers that are
intentionally omitted from the published feed.

## Runtime behavior

If ModemManager reports no modem, the feeder publishes `no-modem`. When several
modems are present, it uses the first connected one. If none are connected, it
publishes `disconnected`. A connected modem with no usable signal measurement
yet (mid-attach, or signal polling not warmed up) publishes `error` rather than
a fabricated value. If ModemManager is unreachable or modem state cannot be
determined reliably, the feeder leaves the last document in place rather than
flapping the feed.

Writes use a temporary file and atomic rename, so the widget never reads a
partial document. The feed file is mode `0644`.

## Privacy

The feeder publishes radio measurements, derived band and neighbour data, and
the operator name. It never publishes IMEI, ICCID, IMSI, TAC, cell ID, or PCI.
`--get-cell-info` responses contain TAC, cell ID, and PCI, but the parser reads
only the EARFCN and RF measurements from each cell and never returns those
identifiers. See [docs/CONTRACT.md](../../docs/CONTRACT.md).
