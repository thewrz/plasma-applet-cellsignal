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
