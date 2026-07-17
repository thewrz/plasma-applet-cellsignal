import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    readonly property var feed: root.feed
    readonly property bool live: root.connected

    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: row.implicitHeight
    onClicked: root.expanded = !root.expanded

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        opacity: compact.live ? 1.0 : 0.5

        Bars {
            visible: plasmoid.configuration.showBars
            Layout.preferredHeight: Math.min(compact.height * 0.7, Kirigami.Units.gridUnit * 1.2)
            Layout.alignment: Qt.AlignVCenter
            rsrp: compact.live && typeof feed.metrics.rsrp_dbm === "number" ? feed.metrics.rsrp_dbm : NaN
        }

        Sparkline {
            visible: plasmoid.configuration.showSparkline
            samples: root.history
            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
            Layout.preferredHeight: Math.min(compact.height * 0.8, Kirigami.Units.gridUnit * 1.4)
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter
            visible: plasmoid.configuration.showBand || plasmoid.configuration.showFrequency || plasmoid.configuration.showTech

            PlasmaComponents.Label {
                visible: plasmoid.configuration.showBand
                text: compact.live && feed.cell.band ? feed.cell.band : "—"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: true
            }
            PlasmaComponents.Label {
                visible: plasmoid.configuration.showFrequency && compact.live && feed.cell.freq_mhz != null
                text: compact.live && feed.cell.freq_mhz != null ? feed.cell.freq_mhz + " MHz" : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                opacity: 0.7
            }
            PlasmaComponents.Label {
                visible: plasmoid.configuration.showTech && compact.live && feed.tech
                text: compact.live && feed.tech ? feed.tech.toUpperCase() : ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.85
                opacity: 0.7
            }
        }
    }
}
