# XMM7360 feeder

This feeder publishes Intel XMM7360 radio measurements for the Cell Signal
Plasma widget. It uses the AT command port exposed by the in-tree `iosm` driver
and does not require the older XMM7360 RPC userspace tools.

## Status

The current feeder emits [contract v2](../../docs/CONTRACT.md). Its parsers and
document builder are covered by captured-shape fixtures with synthetic
identifiers. The AT commands were checked on XMM7360 hardware. A full manual
pass with the v2 feeder installed and feeding the live Plasma HUD remains to be
done.

Contract v1 remains compatible with the applet, but an older installed feeder
must be replaced before the v2 fields will appear.

## Requirements

- an Intel XMM7360 modem using the `iosm` kernel driver
- `/dev/wwan0at1` as the responsive AT command port
- a `wwan0` interface with a global IPv4 or IPv6 address when connected
- Python 3 and systemd
- root access for the feeder because the AT device is normally mode `0600`

The built-in EARFCN table currently labels the LTE bands used by the original
AT&T deployment: B2, B4, B5, B12, B14, B17, B29, B30, B66, and B71. Other
EARFCNs can still carry measurements, but their band and nominal frequency are
reported as unknown until the table is extended.

## Published data

Each successful connected sample can include:

| Data | Modem source |
|---|---|
| RSRP, RSRQ, SNR, serving EARFCN, and timing advance | `AT+XMCI=1` |
| Fallback signal metrics when XMCI omits RSRP | `AT+XCESQ?` |
| Serving bandwidth and carrier aggregation | `AT+GTCAINFO?` |
| RRC connected or idle state | `AT+CSCON?` |
| Registered operator name | `AT+COPS?` |

Timing advance is converted to an estimated one-way radio-path distance at
about 78 metres per step. It is not a GPS fix or a road distance.

The operator result is cached for five minutes, including an unavailable
result, so most samples do not send `AT+COPS?`.

## Install or upgrade

Run these commands from `feeders/xmm7360/`:

```sh
sudo systemctl stop cellsignal-xmm7360.timer cellsignal-xmm7360.service
sudo install -Dm755 cellsignal-feeder-xmm7360 /usr/local/bin/cellsignal-feeder-xmm7360
sudo install -Dm755 xmm7360_decode.py /usr/local/bin/xmm7360_decode.py
sudo install -Dm644 cellsignal-xmm7360.service /etc/systemd/system/cellsignal-xmm7360.service
sudo install -Dm644 cellsignal-xmm7360.timer /etc/systemd/system/cellsignal-xmm7360.timer
sudo systemctl daemon-reload
sudo systemctl enable --now cellsignal-xmm7360.timer
```

The same commands upgrade an existing installation. Stopping the timer and its
service first prevents a sample from starting between the two Python-file
installs. Both files must be updated together.

Run one sample immediately and inspect the result:

```sh
sudo systemctl start --wait cellsignal-xmm7360.service
python3 -m json.tool /run/cellsignal.json
systemctl status cellsignal-xmm7360.timer
```

A current connected feed starts with `"version": 2`. The timer runs every two
seconds after an initial 30-second delay at boot.

## Direct diagnostics

These modes run one sample without changing the timer:

```sh
sudo /usr/local/bin/cellsignal-feeder-xmm7360 --print
sudo /usr/local/bin/cellsignal-feeder-xmm7360 --debug
```

`--debug` prints the AT request and response traffic to stderr. Review that
output before sharing it because raw modem responses contain cell identifiers
that are intentionally omitted from the published feed.

## Runtime behavior

The feeder serializes AT access with `/run/lte-at.lock`. If another tool holds
the lock, or an AT session times out, the feeder leaves the last document in
place. Writes to `/run/cellsignal.json` use a temporary file and atomic rename,
so the applet does not read a partial document.

If `/dev/wwan0at1` is missing, the feeder publishes `no-modem`. If `wwan0` has
no global address, it publishes `disconnected`. A responsive modem without a
usable RSRP sample produces `error` rather than a fabricated value.

If another periodic modem tool uses the same lock, repeated skipped samples can
eventually make the applet mark the feed stale. Disable the redundant publisher
or adjust its schedule.

## Privacy

The feeder publishes radio measurements, derived distance and neighbour data,
the operator name, and limited operational metadata. It never publishes IMEI,
ICCID, IMSI, TAC, cell ID, or PCI. TAC, cell ID, and PCI are present in some
raw `XMCI` and `GTCAINFO` responses, but the parsers read past them and do not
return them. `/run/cellsignal.json` is mode `0644` so the unprivileged applet
can read it; other local users can read it too.
