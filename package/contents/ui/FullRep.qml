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
                rsrp: full.live && typeof feed.metrics.rsrp_dbm === "number" ? feed.metrics.rsrp_dbm : NaN
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: {
                    if (!full.live) return ""
                    var parts = []
                    var band = feed.cell.band || root.lastBand
                    if (band) parts.push(band)
                    if (feed.cell.freq_mhz != null) parts.push(feed.cell.freq_mhz + " MHz")
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
