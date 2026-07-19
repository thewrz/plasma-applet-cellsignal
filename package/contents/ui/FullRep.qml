import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "hud" as Hud

// Popup (full) representation: the two-column HUD dashboard ("Layout B").
// Left column = animated metric bars + history sparkline + tower distance.
// Right column = cell key/value stack + neighbour chips. Null fields dim or
// collapse; a disconnected/stale feed renders the frame with a status line.
Item {
    id: full

    readonly property var feed: root.feed
    readonly property bool live: root.connected

    // Convenience null-safe cell accessors (v1 docs lack the v2 fields, which
    // read back as undefined -> treated as absent via `!= null`).
    readonly property var cell: feed && feed.cell ? feed.cell : null
    readonly property string bandText: full.live ? (cell.band || root.lastBand || "") : ""

    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.minimumHeight: Kirigami.Units.gridUnit * 15
    implicitWidth: Kirigami.Units.gridUnit * 24
    implicitHeight: Kirigami.Units.gridUnit * 16

    Hud.HudFrame {
        anchors.fill: parent
        accent: root.accentColor
        glowIntensity: root.glowIntensity

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            // --- Title row ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Text {
                    text: i18n("CELL SIGNAL")
                    color: root.accentColor
                    font.family: Hud.HudStyle.fontMono
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                }

                // RRC state dot: pulses while RRC-connected.
                Rectangle {
                    id: rrcDot
                    visible: plasmoid.configuration.showRrc
                    readonly property string rrc: (full.cell && full.cell.rrc_state != null)
                                                  ? full.cell.rrc_state : ""
                    readonly property bool rrcConnected: rrc === "connected"
                    width: Kirigami.Units.gridUnit * 0.6
                    height: width
                    radius: width / 2
                    color: rrcConnected ? root.accentColor
                         : rrc === "idle" ? Hud.HudStyle.textDim
                         : Hud.HudStyle.textFaint
                    opacity: rrc === "" ? 0.4 : 1

                    SequentialAnimation {
                        running: rrcDot.rrcConnected && root.animationsEnabled
                        loops: Animation.Infinite
                        NumberAnimation {
                            target: rrcDot; property: "opacity"
                            from: 1.0; to: 0.3
                            duration: Kirigami.Units.veryLongDuration
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            target: rrcDot; property: "opacity"
                            from: 0.3; to: 1.0
                            duration: Kirigami.Units.veryLongDuration
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: {
                        if (!full.live) return ""
                        var parts = []
                        if (feed.operator) parts.push(feed.operator)
                        if (feed.tech) parts.push(feed.tech.toUpperCase())
                        return parts.join(" · ")
                    }
                    color: Hud.HudStyle.textDim
                    font.family: Hud.HudStyle.fontMono
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.25)
            }

            // --- Status line (not live) ---
            Item {
                visible: !full.live
                Layout.fillWidth: true
                Layout.fillHeight: true
                Text {
                    anchors.centerIn: parent
                    text: !feed ? i18n("NO FEED")
                        : root.stale ? i18n("FEED STALE")
                        : feed.state.toUpperCase()
                    color: Hud.HudStyle.textDim
                    font.family: Hud.HudStyle.fontMono
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                }
            }

            // --- Two-column dashboard (live) ---
            RowLayout {
                visible: full.live
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                // Left column: metrics + sparkline + tower.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: Kirigami.Units.smallSpacing

                    MetricBar {
                        visible: plasmoid.configuration.showRsrp
                        label: "RSRP"; unit: "dBm"; rangeLo: -125; rangeHi: -75; decimals: 0
                        accent: root.accentColor; animate: root.animationsEnabled
                        value: full.live ? feed.metrics.rsrp_dbm : null
                    }
                    MetricBar {
                        visible: plasmoid.configuration.showRsrq
                        label: "RSRQ"; unit: "dB"; rangeLo: -20; rangeHi: -3
                        accent: root.accentColor; animate: root.animationsEnabled
                        value: full.live ? feed.metrics.rsrq_db : null
                    }
                    MetricBar {
                        visible: plasmoid.configuration.showSnr
                        label: "SNR"; unit: "dB"; rangeLo: -10; rangeHi: 30
                        accent: root.accentColor; animate: root.animationsEnabled
                        value: full.live ? feed.metrics.snr_db : null
                    }
                    MetricBar {
                        label: "QUAL"; unit: "%"; rangeLo: 0; rangeHi: 100; decimals: 0
                        accent: root.accentColor; animate: root.animationsEnabled
                        value: full.live && typeof feed.quality_pct === "number"
                               ? feed.quality_pct : null
                    }

                    Text {
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: i18n("HISTORY (%1)",
                                   plasmoid.configuration.sparklineMetric.split("_")[0].toUpperCase())
                        color: Hud.HudStyle.textDim
                        font.family: Hud.HudStyle.fontMono
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    Sparkline {
                        samples: root.history
                        accent: root.accentColor
                        glow: root.glowIntensity > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    }

                    TowerModule {
                        visible: plasmoid.configuration.showDistance && full.live
                                 && full.cell && full.cell.distance_m != null
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        distanceM: full.cell ? full.cell.distance_m : null
                        accent: root.accentColor
                        animate: root.animationsEnabled
                    }

                    Item { Layout.fillHeight: true }
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                }

                // Right column: cell key/values + neighbours.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: Kirigami.Units.smallSpacing

                    KvRow {
                        visible: full.bandText !== ""
                        key: i18n("Band"); value: full.bandText
                        accent: root.accentColor
                    }
                    KvRow {
                        visible: full.live && full.cell && full.cell.freq_mhz != null
                        key: i18n("Freq")
                        value: (full.cell && full.cell.freq_mhz != null)
                               ? full.cell.freq_mhz + " MHz" : ""
                        accent: root.accentColor
                    }
                    KvRow {
                        visible: plasmoid.configuration.showBandwidth && full.live
                                 && full.cell && full.cell.bandwidth_mhz != null
                        key: i18n("Bandwidth")
                        value: (full.cell && full.cell.bandwidth_mhz != null)
                               ? full.cell.bandwidth_mhz + " MHz" : ""
                        accent: root.accentColor
                    }
                    KvRow {
                        visible: full.live && full.cell && full.cell.earfcn != null
                        key: i18n("EARFCN")
                        value: (full.cell && full.cell.earfcn != null)
                               ? "" + full.cell.earfcn : ""
                        accent: root.accentColor
                    }
                    KvRow {
                        visible: plasmoid.configuration.showAggregation && full.live
                                 && feed.aggregation != null
                        key: i18n("Carrier agg")
                        value: {
                            if (!full.live || feed.aggregation == null) return ""
                            var a = feed.aggregation
                            var bands = (a.bands && a.bands.length) ? a.bands.join("+") : ""
                            var mhz = (a.aggregate_mhz != null) ? a.aggregate_mhz + " MHz" : ""
                            return [bands, mhz].filter(function (s) { return s !== "" }).join(" · ")
                        }
                        accent: root.accentColor
                    }

                    Text {
                        visible: plasmoid.configuration.showNeighbors && full.live
                                 && neighbors.count > 0
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        text: i18n("NEIGHBOURS")
                        color: Hud.HudStyle.textDim
                        font.family: Hud.HudStyle.fontMono
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                    NeighborList {
                        id: neighbors
                        visible: plasmoid.configuration.showNeighbors && full.live && count > 0
                        Layout.fillWidth: true
                        neighbors: (full.live && feed.neighbors) ? feed.neighbors : []
                        accent: root.accentColor
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
