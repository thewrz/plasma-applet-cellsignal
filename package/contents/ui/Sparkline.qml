import QtQuick
import org.kde.kirigami as Kirigami

// Scrolling history line of the configured metric. Auto-scales to the sample
// range (with a minimum span so noise doesn't fill the height). Theme accent.
Canvas {
    id: canvas
    property var samples: []
    property real minSpan: 10   // dB(m) — minimum vertical span

    onSamplesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
        target: Kirigami.Theme
        function onColorsChanged() { canvas.requestPaint() }
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!samples || samples.length < 2) return

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

        var accent = Kirigami.Theme.highlightColor
        ctx.beginPath()
        ctx.moveTo(0, yFor(samples[0]))
        for (var i = 1; i < samples.length; i++)
            ctx.lineTo(i * stepX, yFor(samples[i]))
        ctx.lineWidth = Math.max(1, height / 14)
        ctx.strokeStyle = accent
        ctx.stroke()

        // translucent fill under the line
        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.18)
        ctx.fill()
    }
}
