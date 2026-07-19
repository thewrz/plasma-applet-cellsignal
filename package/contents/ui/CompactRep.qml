import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "hud" as Hud

// Panel (compact) representation: a dark HUD mini-strip inside HudFrame —
// glowing bars, a glow-endpoint sparkline, and a neon band/freq/tech label.
// Each element stays individually toggleable via the existing config.
MouseArea {
    id: compact

    readonly property var feed: root.feed
    readonly property bool live: root.connected

    implicitWidth: frame.implicitWidth
    implicitHeight: frame.implicitHeight
    onClicked: root.expanded = !root.expanded

    Hud.HudFrame {
        id: frame
        anchors.fill: parent
        accent: root.accentColor
        glowIntensity: root.glowIntensity
        chamfer: Math.min(Hud.HudStyle.chamfer, compact.height * 0.35)

        RowLayout {
            id: row
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing
            opacity: compact.live ? 1.0 : 0.5

            Bars {
                visible: plasmoid.configuration.showBars
                accent: root.accentColor
                animate: root.animationsEnabled
                Layout.preferredHeight: Math.min(compact.height * 0.6, Kirigami.Units.gridUnit * 1.2)
                Layout.alignment: Qt.AlignVCenter
                rsrp: compact.live && typeof feed.metrics.rsrp_dbm === "number"
                      ? feed.metrics.rsrp_dbm : NaN
            }

            Sparkline {
                visible: plasmoid.configuration.showSparkline
                samples: root.history
                accent: root.accentColor
                glow: root.glowIntensity > 0
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                Layout.preferredHeight: Math.min(compact.height * 0.7, Kirigami.Units.gridUnit * 1.4)
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignVCenter
                visible: plasmoid.configuration.showBand
                         || plasmoid.configuration.showFrequency
                         || plasmoid.configuration.showTech

                Text {
                    visible: plasmoid.configuration.showBand
                    text: compact.live ? (feed.cell.band || root.lastBand || "—") : "—"
                    color: root.accentColor
                    font.family: Hud.HudStyle.fontMono
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                }
                Text {
                    visible: plasmoid.configuration.showFrequency && compact.live
                             && feed.cell.freq_mhz != null
                    text: compact.live && feed.cell.freq_mhz != null
                          ? feed.cell.freq_mhz + " MHz" : ""
                    color: Hud.HudStyle.textDim
                    font.family: Hud.HudStyle.fontMono
                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                }
                Text {
                    visible: plasmoid.configuration.showTech && compact.live && feed.tech
                    text: compact.live && feed.tech ? feed.tech.toUpperCase() : ""
                    color: Hud.HudStyle.textDim
                    font.family: Hud.HudStyle.fontMono
                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                }
            }
        }
    }
}
