import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "hud" as Hud

// Distance-to-tower readout: a small radar with concentric range rings that
// pulse outward when live, plus the distance label. Distance comes from the v2
// `cell.distance_m` (derived from timing advance). Null distance dims the
// module. Pulsing is gated on the platform reduced-animation setting.
RowLayout {
    id: tower

    property var distanceM: null      // number (metres) or null
    property color accent: Hud.HudStyle.accentGood
    property bool animate: true

    readonly property bool hasDistance: typeof distanceM === "number" && isFinite(distanceM)
    readonly property string distanceText: !hasDistance ? "—"
        : (distanceM >= 1000 ? (distanceM / 1000).toFixed(2) + " km"
                             : Math.round(distanceM) + " m")

    spacing: Kirigami.Units.largeSpacing
    opacity: hasDistance ? 1 : 0.4

    Item {
        id: radar
        readonly property real dim: Kirigami.Units.gridUnit * 3.5
        Layout.preferredWidth: dim
        Layout.preferredHeight: dim

        // Static range rings.
        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real f: (index + 1) / 3
                width: radar.dim * f
                height: width
                radius: width / 2
                anchors.centerIn: parent
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(tower.accent.r, tower.accent.g, tower.accent.b,
                                      0.35 - index * 0.08)
            }
        }

        // Pulsing sweep ring: expands from the centre and fades, then repeats.
        Rectangle {
            id: pulse
            anchors.centerIn: parent
            width: radar.dim
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: tower.accent
            transformOrigin: Item.Center

            readonly property bool active: tower.hasDistance && tower.animate
            visible: active
            scale: 0.1
            opacity: 0

            SequentialAnimation {
                running: pulse.active
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation {
                        target: pulse; property: "scale"
                        from: 0.1; to: 1.0
                        duration: Kirigami.Units.veryLongDuration * 2
                        easing.type: Easing.OutQuad
                    }
                    SequentialAnimation {
                        NumberAnimation {
                            target: pulse; property: "opacity"
                            from: 0.0; to: 0.6
                            duration: Kirigami.Units.veryLongDuration / 2
                        }
                        NumberAnimation {
                            target: pulse; property: "opacity"
                            to: 0.0
                            duration: Kirigami.Units.veryLongDuration * 1.5
                        }
                    }
                }
            }
        }

        // Centre marker: the device.
        Rectangle {
            anchors.centerIn: parent
            width: Kirigami.Units.smallSpacing * 1.5
            height: width
            radius: width / 2
            color: tower.accent
        }
    }

    ColumnLayout {
        spacing: 0
        Text {
            text: i18n("Tower")
            color: Hud.HudStyle.textDim
            font.family: Hud.HudStyle.fontMono
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
        Text {
            text: tower.distanceText
            color: tower.hasDistance ? Hud.HudStyle.textBright : Hud.HudStyle.textFaint
            font.family: Hud.HudStyle.fontMono
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            font.bold: true
        }
    }
}
