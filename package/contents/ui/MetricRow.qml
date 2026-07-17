import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One metric line: name, value+unit, level bar normalized to [rangeLo, rangeHi].
RowLayout {
    id: metricRow
    property string label
    property var value: null      // number or null
    property string unit
    property real rangeLo
    property real rangeHi
    property int decimals: 1

    readonly property real norm: value === null ? 0
        : Math.max(0, Math.min(1, (value - rangeLo) / (rangeHi - rangeLo)))

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    PlasmaComponents.Label {
        text: metricRow.label
        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
        opacity: 0.7
    }
    PlasmaComponents.Label {
        text: metricRow.value === null ? "—"
              : metricRow.value.toFixed(metricRow.decimals) + " " + metricRow.unit
        font.family: "monospace"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5
        horizontalAlignment: Text.AlignRight
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit / 3)
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        Rectangle {
            width: parent.width * metricRow.norm
            height: parent.height
            radius: height / 2
            color: metricRow.norm > 0.55 ? Kirigami.Theme.positiveTextColor
                 : metricRow.norm > 0.3 ? Kirigami.Theme.neutralTextColor
                 : Kirigami.Theme.negativeTextColor
            opacity: metricRow.value === null ? 0 : 1
            Behavior on width { NumberAnimation { duration: 250 } }
        }
    }
}
