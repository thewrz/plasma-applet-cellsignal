import QtQuick
import org.kde.kirigami as Kirigami
import "hud" as Hud

// Scrolling history line of the configured metric, HUD-styled: accent line with
// a soft glow and a glowing head dot at the live edge. Auto-scales to the
// sample range (with a minimum span so noise doesn't fill the height). The
// accent flows in from the caller so it re-tints with the rest of the HUD.
Canvas {
    id: canvas

    property var samples: []
    property color accent: Hud.HudStyle.accentGood
    property bool glow: true
    // Minimum vertical span in dB(m). Small on purpose: indoor RSRP moves in
    // sub-dB steps, and a wide floor flattens that real motion into sub-pixel
    // territory. 3 dB keeps micro-variation visible without amplifying noise
    // into drama.
    property real minSpan: 3

    onSamplesChanged: requestPaint()
    onAccentChanged: requestPaint()
    onGlowChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (!samples || samples.length < 2)
            return

        var lo = Math.min.apply(null, samples)
        var hi = Math.max.apply(null, samples)
        var mid = (lo + hi) / 2
        var span = Math.max(hi - lo, minSpan)
        lo = mid - span / 2
        hi = mid + span / 2

        var stepX = width / (samples.length - 1)
        var pad = Math.max(1, height * 0.1)
        function yFor(v) {
            return pad + (1 - (v - lo) / (hi - lo)) * (height - 2 * pad)
        }

        // Line with a soft accent glow.
        ctx.beginPath()
        ctx.moveTo(0, yFor(samples[0]))
        for (var i = 1; i < samples.length; i++)
            ctx.lineTo(i * stepX, yFor(samples[i]))
        ctx.lineWidth = Math.max(1, height / 14)
        ctx.strokeStyle = accent
        if (glow) {
            ctx.shadowColor = accent
            ctx.shadowBlur = Math.max(2, height / 6)
        }
        ctx.stroke()
        ctx.shadowBlur = 0

        // Translucent fill under the line.
        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.18)
        ctx.fill()

        // Head dot marks the live edge — reads as alive even when the line is
        // flat. Clamp the centre a full radius inside the canvas on both axes,
        // or the dot renders mostly clipped at common component sizes.
        var r = Math.max(1.5, height / 9)
        var headX = Math.min((samples.length - 1) * stepX, width - r)
        var headY = Math.min(Math.max(yFor(samples[samples.length - 1]), r), height - r)
        ctx.beginPath()
        ctx.arc(headX, headY, r, 0, 2 * Math.PI)
        ctx.fillStyle = accent
        if (glow) {
            ctx.shadowColor = accent
            ctx.shadowBlur = Math.max(3, height / 4)
        }
        ctx.fill()
    }
}
