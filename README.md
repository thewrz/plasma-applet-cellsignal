# Cell Signal

Cell Signal is a KDE Plasma 6 widget for cellular modem telemetry. It reads a
small JSON document from a separate feeder, so the Plasma code does not need to
know how each modem exposes its measurements.

## Current status

The current tree is version 0.2.1. [PR #21](https://github.com/thewrz/plasma-applet-cellsignal/pull/21)
added feed contract v2 and the expanded XMM7360 feeder. [PR #22](https://github.com/thewrz/plasma-applet-cellsignal/pull/22)
added the two-column cyberpunk detail popup.

The applet accepts both v1 and v2 feed documents. Core signal data still works
with a v1 feeder. The extra cell details appear only when a v2 feeder supplies
them.

Parser, contract, privacy, and headless QML tests cover the merged code. Two
manual checks remain: an installed XMM7360 feeder producing a live v2 document,
and a visual pass of the HUD in Plasma with live, partial, disconnected, and
carrier-aggregation data.

## Display

The compact panel remains theme-aware and can show:

- signal bars and a scrolling RSRP, RSRQ, or SNR history
- LTE band, frequency, and radio technology
- Plasma semantic colors for strong, fair, and weak signal levels

The popup adds:

- RSRP, RSRQ, SNR, and normalized quality bars
- serving band, EARFCN, channel bandwidth, and carrier aggregation
- registered operator, RRC state, detected neighbour cells, and estimated
  distance to the serving tower
- clear no-feed, stale, disconnected, and error states

The popup uses an always-dark HUD palette. Quality controls its accent when
available, with RSRP as the fallback. Plasma's reduced-animation setting also
disables the popup's motion.

## Feeders

| Feeder | Hardware | Status |
|---|---|---|
| [feeders/xmm7360](feeders/xmm7360/) | Intel XMM7360 with the in-tree `iosm` driver | Contract v2 implemented |
| `feeders/mmcli` | ModemManager modems | Planned |

The default feed command is `cat /run/cellsignal.json`. The complete document
format and compatibility rules are in [docs/CONTRACT.md](docs/CONTRACT.md).

## Install the widget

For development, link the checkout into the local Plasma applet directory:

```sh
./install.sh
```

The script replaces any existing local installation of this applet with a
symlink to `package/` and clears Plasma's QML cache. Add **Cell Signal** from the
panel's **Add Widgets** dialog, then install a feeder.

To install a copy instead of a development symlink:

```sh
kpackagetool6 -t Plasma/Applet -i package/
```

Use `-u` instead of `-i` for an existing installation. Reload Plasma after an
install or upgrade so the running widget picks up the new QML:

```sh
systemctl --user restart plasma-plasmashell.service
```

## Configuration

Settings provide individual controls for the panel items, the RSRP, RSRQ, and
SNR popup bars, and the optional v2 cell details. The poll interval is
configurable from 1 to 30 seconds, and the history holds 10 to 600 samples. The
feed command can point at any program that prints a valid contract document.

Popup glow strength and accent mode are also configurable. Fixed popup accent
choices are cyan-green, amber, magenta, ice blue, and lime.

## Development checks

```sh
python3 -m pytest tests/ -q
qmllint package/contents/ui/*.qml package/contents/ui/hud/*.qml
QT_QPA_PLATFORM=offscreen qml6 tests/qml/check_hudstyle.qml
QT_QPA_PLATFORM=offscreen qml6 tests/qml/check_components.qml
QT_QPA_PLATFORM=offscreen qml6 tests/qml/check_panel.qml
QT_QPA_PLATFORM=offscreen qml6 tests/qml/check_main.qml
```

## Privacy

The contract contains radio measurements, derived distance and neighbour data,
an operator name, and limited operational metadata. It has no fields for IMEI,
ICCID, IMSI, TAC, cell ID, or PCI. The XMM7360 responses contain some of those
cell identifiers, but the feeder excludes them from parser output and the
published document. The default feed file is readable by local users.

## License

MIT.
