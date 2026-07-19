import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "hud" as Hud

// Neighbor-cell chips (band + RSRP) from the v2 `neighbors` array. Each entry
// is {band, earfcn, rsrp_dbm, rsrq_db}; band and RSRP may individually be null.
// An empty array collapses to nothing (the caller hides the section header).
ColumnLayout {
    id: neighborList

    property var neighbors: []
    property color accent: Hud.HudStyle.accentGood

    readonly property int count: (neighbors && neighbors.length) ? neighbors.length : 0

    spacing: Kirigami.Units.smallSpacing

    Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: neighborList.neighbors

            Rectangle {
                id: chip
                required property var modelData

                readonly property string bandText: (modelData && modelData.band) ? modelData.band : "?"
                readonly property bool hasRsrp: modelData && typeof modelData.rsrp_dbm === "number"
                                                && isFinite(modelData.rsrp_dbm)
                readonly property string rsrpText: hasRsrp
                    ? modelData.rsrp_dbm.toFixed(0) + " dBm" : "—"

                implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 2
                implicitHeight: chipRow.implicitHeight + Kirigami.Units.smallSpacing
                radius: 3
                color: Hud.HudStyle.chip
                border.width: 1
                border.color: Qt.rgba(neighborList.accent.r, neighborList.accent.g,
                                      neighborList.accent.b, 0.35)

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Text {
                        text: chip.bandText
                        color: neighborList.accent
                        font.family: Hud.HudStyle.fontMono
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.bold: true
                    }
                    Text {
                        text: chip.rsrpText
                        color: chip.hasRsrp ? Hud.HudStyle.textDim : Hud.HudStyle.textFaint
                        font.family: Hud.HudStyle.fontMono
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }
                }
            }
        }
    }
}
