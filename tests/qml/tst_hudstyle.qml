import QtQuick
import QtTest
import "../../package/contents/ui/hud" as Hud

// Unit tests for the signal-reactive color engine (HudStyle.accentFor).
// Runs headless via: QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
TestCase {
    id: tc
    name: "HudStyle"

    function color_eq(a, b) {
        return Math.abs(a.r - b.r) < 0.001
            && Math.abs(a.g - b.g) < 0.001
            && Math.abs(a.b - b.b) < 0.001
    }

    // quality >= 55 -> good (cyan-green)
    function test_quality_good() {
        verify(color_eq(Hud.HudStyle.accentFor(61, -95), Hud.HudStyle.accentGood))
        verify(color_eq(Hud.HudStyle.accentFor(55, -120), Hud.HudStyle.accentGood))
    }

    // 30 <= quality < 55 -> fair (amber)
    function test_quality_fair() {
        verify(color_eq(Hud.HudStyle.accentFor(40, -110), Hud.HudStyle.accentFair))
        verify(color_eq(Hud.HudStyle.accentFor(30, -120), Hud.HudStyle.accentFair))
    }

    // quality < 30 -> weak (magenta)
    function test_quality_weak() {
        verify(color_eq(Hud.HudStyle.accentFor(8, -117), Hud.HudStyle.accentWeak))
        verify(color_eq(Hud.HudStyle.accentFor(0, -130), Hud.HudStyle.accentWeak))
    }

    // quality absent: RSRP fallback. >= -95 -> good
    function test_rsrp_fallback_good() {
        verify(color_eq(Hud.HudStyle.accentFor(null, -90), Hud.HudStyle.accentGood))
        verify(color_eq(Hud.HudStyle.accentFor(null, -95), Hud.HudStyle.accentGood))
    }

    // quality absent: RSRP fallback fair/weak bands
    function test_rsrp_fallback_fair_weak() {
        verify(color_eq(Hud.HudStyle.accentFor(null, -100), Hud.HudStyle.accentFair))
        verify(color_eq(Hud.HudStyle.accentFor(null, -115), Hud.HudStyle.accentWeak))
    }

    // no data at all -> idle (neither reactive band)
    function test_no_data_idle() {
        verify(color_eq(Hud.HudStyle.accentFor(null, null), Hud.HudStyle.accentIdle))
    }

    // NaN / non-finite treated as absent, not a numeric band
    function test_non_finite_ignored() {
        verify(color_eq(Hud.HudStyle.accentFor(NaN, -90), Hud.HudStyle.accentGood))
        verify(color_eq(Hud.HudStyle.accentFor(NaN, NaN), Hud.HudStyle.accentIdle))
    }
}
