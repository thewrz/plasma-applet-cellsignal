import QtQuick
import "../../package/contents/ui/hud" as Hud

// Headless assertion harness for the color engine, runnable where the QtTest
// runner is unavailable:
//   QT_QPA_PLATFORM=offscreen qml6 tests/qml/check_hudstyle.qml
// Exits 0 when every case passes, 1 otherwise. tst_hudstyle.qml is the same
// contract expressed as a proper TestCase for environments with qmltestrunner.
Item {
    function eq(a, b) {
        return Math.abs(a.r - b.r) < 0.001
            && Math.abs(a.g - b.g) < 0.001
            && Math.abs(a.b - b.b) < 0.001
    }

    Component.onCompleted: {
        var S = Hud.HudStyle
        var cases = [
            [S.accentFor(61, -95),   S.accentGood, "quality>=55 good"],
            [S.accentFor(55, -120),  S.accentGood, "quality=55 good"],
            [S.accentFor(40, -110),  S.accentFair, "quality 40 fair"],
            [S.accentFor(30, -120),  S.accentFair, "quality=30 fair"],
            [S.accentFor(8, -117),   S.accentWeak, "quality 8 weak"],
            [S.accentFor(0, -130),   S.accentWeak, "quality 0 weak"],
            [S.accentFor(null, -90), S.accentGood, "rsrp>=-95 good"],
            [S.accentFor(null, -95), S.accentGood, "rsrp=-95 good"],
            [S.accentFor(null, -100),S.accentFair, "rsrp -100 fair"],
            [S.accentFor(null, -115),S.accentWeak, "rsrp -115 weak"],
            [S.accentFor(null, null),S.accentIdle, "no data idle"],
            [S.accentFor(NaN, -90),  S.accentGood, "NaN quality -> rsrp good"],
            [S.accentFor(NaN, NaN),  S.accentIdle, "all non-finite idle"]
        ]
        var failed = 0
        for (var i = 0; i < cases.length; i++) {
            if (!eq(cases[i][0], cases[i][1])) {
                console.log("FAIL:", cases[i][2])
                failed++
            }
        }
        if (failed === 0)
            console.log("PASS: all " + cases.length + " accentFor cases")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
