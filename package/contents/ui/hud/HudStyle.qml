pragma Singleton
import QtQuick

// Shared HUD design tokens + the signal-reactive color engine.
//
// The HUD is a deliberately single-look, always-dark element (the approved
// exception to desktop theme-adaptivity). These tokens are the one place the
// palette lives; every component draws its accent from `accentFor(...)` so the
// whole widget re-tints together — nothing hardcodes a per-component color.
QtObject {
    id: style

    // --- Accent palette (signal-reactive) ---
    readonly property color accentGood: "#29e7cd"   // cyan-green: strong signal
    readonly property color accentFair: "#ffb020"   // amber: fair signal
    readonly property color accentWeak: "#ff3b8b"   // magenta: weak signal
    readonly property color accentIdle: "#3a4b5c"   // muted: no data / disconnected

    // --- Dark grounds ---
    readonly property color ground: "#070b12"           // panel base
    readonly property color groundPanel: "#0d1420"      // raised surface
    readonly property color chip: "#12202e"             // small inset (chips, kv)

    // --- Text ---
    readonly property color textBright: "#dbe7f2"
    readonly property color textDim: "#7f93a6"
    readonly property color textFaint: "#4c5d6e"

    // --- Typography ---
    // Generic monospace family; Qt resolves it to the platform's mono face.
    readonly property string fontMono: "monospace"

    // --- Geometry / glow ---
    readonly property real chamfer: 12        // clipped-corner size (px)
    readonly property real gridStep: 16       // faint grid spacing (px)
    readonly property real borderWidth: 1.5

    // Signal-reactive accent. Pure: same inputs -> same color, no side effects.
    //
    //   quality (0-100, may be null) is authoritative; RSRP (dBm, may be null)
    //   is the fallback when quality is absent. Non-finite values are treated
    //   as absent. Bands (spec):
    //     good : quality >= 55   (fallback RSRP >= -95)
    //     fair : 30 <= quality < 55
    //     weak : quality < 30
    //   With no usable input at all, returns the muted idle accent.
    function accentFor(quality, rsrp) {
        var q = (typeof quality === "number" && isFinite(quality)) ? quality : null
        var r = (typeof rsrp === "number" && isFinite(rsrp)) ? rsrp : null

        if (q !== null) {
            if (q >= 55) return accentGood
            if (q >= 30) return accentFair
            return accentWeak
        }
        if (r !== null) {
            if (r >= -95) return accentGood
            if (r >= -105) return accentFair
            return accentWeak
        }
        return accentIdle
    }
}
