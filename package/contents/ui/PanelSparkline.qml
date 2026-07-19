import QtQuick
import org.kde.kirigami as Kirigami

// Theme-aware scrolling history used by the compact panel representation.
Canvas {
    id: canvas
    property var samples: []
    property real minSpan: 3

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

        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.18)
        ctx.fill()

        var r = Math.max(1.5, height / 9)
        var headX = Math.min((samples.length - 1) * stepX, width - r)
        var headY = Math.min(Math.max(yFor(samples[samples.length - 1]), r), height - r)
        ctx.beginPath()
        ctx.arc(headX, headY, r, 0, 2 * Math.PI)
        ctx.fillStyle = accent
        ctx.fill()
    }
}
