import QtQuick
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as UI

// Pin the compact panel's pre-HUD signal semantics: stepped bars use Plasma's
// negative, neutral and positive colors, and its sparkline remains theme-aware.
Item {
    UI.Bars { id: weakBars; width: 60; height: 30; rsrp: -115 }
    UI.Bars { id: fairBars; width: 60; height: 30; rsrp: -105 }
    UI.Bars { id: strongBars; width: 60; height: 30; rsrp: -95 }
    UI.PanelSparkline {
        width: 120
        height: 40
        samples: [-106, -104, -105, -103]
    }

    function sameColor(left, right) {
        return Math.abs(left.r - right.r) < 0.001
            && Math.abs(left.g - right.g) < 0.001
            && Math.abs(left.b - right.b) < 0.001
            && Math.abs(left.a - right.a) < 0.001
    }

    Component.onCompleted: {
        var valid = weakBars.level === 1
            && fairBars.level === 2
            && strongBars.level === 3
            && sameColor(weakBars.levelColor, Kirigami.Theme.negativeTextColor)
            && sameColor(fairBars.levelColor, Kirigami.Theme.neutralTextColor)
            && sameColor(strongBars.levelColor, Kirigami.Theme.positiveTextColor)
        if (!valid) {
            console.error("FAIL: compact panel signal semantics changed")
            Qt.exit(1)
            return
        }
        console.log("PANEL_OK")
        Qt.exit(0)
    }
}
