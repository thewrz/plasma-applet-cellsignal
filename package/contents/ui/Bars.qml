import QtQuick
import org.kde.kirigami as Kirigami

// 4 stepped signal bars driven by RSRP. Theme-semantic colors:
// 4-3 bars positive, 2 neutral, 1-0 negative. NaN -> all empty.
Row {
    id: bars
    property real rsrp: NaN

    readonly property int level: {
        if (isNaN(rsrp)) return 0
        if (rsrp >= -90) return 4
        if (rsrp >= -100) return 3
        if (rsrp >= -110) return 2
        if (rsrp >= -120) return 1
        return 0
    }
    readonly property color levelColor: level >= 3 ? Kirigami.Theme.positiveTextColor
                                       : level === 2 ? Kirigami.Theme.neutralTextColor
                                       : Kirigami.Theme.negativeTextColor

    spacing: Math.max(1, Math.round(height / 12))

    Repeater {
        model: 4
        Rectangle {
            required property int index
            width: Math.max(2, Math.round(bars.height / 5))
            height: bars.height * (0.4 + 0.2 * index)
            anchors.bottom: parent.bottom
            radius: width / 3
            color: index < bars.level ? bars.levelColor : Kirigami.Theme.textColor
            opacity: index < bars.level ? 1.0 : 0.25
            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }
}
