import QtQuick
import org.kde.kirigami as Kirigami
import "hud" as Hud

// 4 stepped signal bars driven by RSRP, HUD-styled: filled bars glow in the
// shared accent, empty bars sit as faint dark stubs. NaN -> all empty. The
// accent flows in from the caller (root.accentColor) so the bars re-tint with
// the rest of the HUD.
Row {
    id: bars

    property real rsrp: NaN
    property color accent: Hud.HudStyle.accentGood
    property bool animate: true

    readonly property int level: {
        if (isNaN(rsrp)) return 0
        if (rsrp >= -90) return 4
        if (rsrp >= -100) return 3
        if (rsrp >= -110) return 2
        if (rsrp >= -120) return 1
        return 0
    }

    spacing: Math.max(1, Math.round(height / 12))

    Repeater {
        model: 4
        Item {
            id: slot
            required property int index
            readonly property bool on: index < bars.level
            width: Math.max(2, Math.round(bars.height / 5))
            height: bars.height * (0.4 + 0.2 * index)
            anchors.bottom: parent.bottom

            // Glow halo behind lit bars.
            Rectangle {
                anchors.centerIn: core
                width: core.width + Kirigami.Units.smallSpacing
                height: core.height + Kirigami.Units.smallSpacing / 2
                radius: width / 2
                color: bars.accent
                opacity: slot.on ? 0.28 : 0
                visible: slot.on
                Behavior on opacity {
                    enabled: bars.animate
                    NumberAnimation { duration: Kirigami.Units.longDuration }
                }
            }
            Rectangle {
                id: core
                anchors.fill: parent
                radius: width / 3
                color: slot.on ? bars.accent : Hud.HudStyle.textDim
                opacity: slot.on ? 1.0 : 0.22
                Behavior on color {
                    enabled: bars.animate
                    ColorAnimation { duration: Kirigami.Units.longDuration }
                }
            }
        }
    }
}
