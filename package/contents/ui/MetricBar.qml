import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "hud" as Hud

// One HUD metric row: mono label, right-aligned mono value+unit, and an
// accent-filled track normalized to [rangeLo, rangeHi]. The fill eases on
// change (gated on the platform reduced-animation setting). A null/non-finite
// value dims the row and empties the track.
RowLayout {
    id: metricBar

    property string label
    property var value: null          // number or null
    property string unit
    property real rangeLo
    property real rangeHi
    property int decimals: 1
    property color accent: Hud.HudStyle.accentGood
    property bool animate: true

    // Guards null, undefined (field absent in a v1 doc), and non-numeric input.
    readonly property bool hasValue: typeof value === "number" && isFinite(value)
    readonly property real norm: !hasValue ? 0
        : Math.max(0, Math.min(1, (value - rangeLo) / (rangeHi - rangeLo)))

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true
    opacity: hasValue ? 1 : 0.4

    Text {
        text: metricBar.label
        color: Hud.HudStyle.textDim
        font.family: Hud.HudStyle.fontMono
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
    }
    Text {
        text: !metricBar.hasValue ? "—"
              : metricBar.value.toFixed(metricBar.decimals) + " " + metricBar.unit
        color: metricBar.hasValue ? Hud.HudStyle.textBright : Hud.HudStyle.textFaint
        font.family: Hud.HudStyle.fontMono
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Kirigami.Units.gridUnit * 5.5
    }
    Rectangle {
        id: track
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit / 3)
        radius: 2
        color: Hud.HudStyle.chip
        border.width: 1
        border.color: Qt.rgba(metricBar.accent.r, metricBar.accent.g, metricBar.accent.b, 0.25)

        Rectangle {
            width: parent.width * metricBar.norm
            height: parent.height
            radius: parent.radius
            color: metricBar.accent
            opacity: metricBar.hasValue ? 0.9 : 0
            Behavior on width {
                enabled: metricBar.animate
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
