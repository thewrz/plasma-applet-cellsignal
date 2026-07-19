import QtQuick
import "." as Hud

// Reusable clipped-corner ("chamfered") dark HUD panel shell: dark ground,
// faint accent-tinted grid, glowing accent border. Wraps arbitrary content via
// its default property, so both the panel and the popup reuse one frame.
Item {
    id: frame

    // Accent flows in from the caller (ultimately HudStyle.accentFor). Never
    // hardcode a color here — the whole HUD re-tints from this one input.
    property color accent: Hud.HudStyle.accentGood
    // 0..1 glow strength (config-controlled). 0 = flat border, no glow.
    property real glowIntensity: 0.6
    property real chamfer: Hud.HudStyle.chamfer

    default property alias content: contentHolder.data
    // Inset so content clears the chamfered corners and glow border.
    property real contentPadding: Math.round(chamfer * 0.9)

    // A plain Item never aggregates its child's implicit size, so read it from
    // the wrapped content (a Layout/positioner computes its own implicitWidth/
    // Height even when anchored fill). Without this the frame would report only
    // 2×contentPadding and collapse the panel representation to a sliver.
    implicitWidth: (contentHolder.children.length > 0
                    ? contentHolder.children[0].implicitWidth : 0) + contentPadding * 2
    implicitHeight: (contentHolder.children.length > 0
                     ? contentHolder.children[0].implicitHeight : 0) + contentPadding * 2

    Canvas {
        id: bg
        anchors.fill: parent
        // Repaint whenever anything that changes the drawing changes.
        readonly property color accent: frame.accent
        readonly property real glowIntensity: frame.glowIntensity
        readonly property real chamfer: frame.chamfer
        onAccentChanged: requestPaint()
        onGlowIntensityChanged: requestPaint()
        onChamferChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (width < 4 || height < 4)
                return

            var c = Math.max(0, Math.min(chamfer, Math.min(width, height) / 2))
            var bw = Hud.HudStyle.borderWidth
            var inset = bw / 2 + 0.5

            // Chamfered path: clip the top-left and bottom-right corners for the
            // asymmetric HUD look; keep the other two square.
            function tracePath() {
                ctx.beginPath()
                ctx.moveTo(inset + c, inset)
                ctx.lineTo(width - inset, inset)
                ctx.lineTo(width - inset, height - inset - c)
                ctx.lineTo(width - inset - c, height - inset)
                ctx.lineTo(inset, height - inset)
                ctx.lineTo(inset, inset + c)
                ctx.closePath()
            }

            // Fill: dark ground with a faint vertical gradient.
            tracePath()
            var g = ctx.createLinearGradient(0, 0, 0, height)
            g.addColorStop(0, Qt.rgba(Hud.HudStyle.groundPanel.r, Hud.HudStyle.groundPanel.g,
                                      Hud.HudStyle.groundPanel.b, 0.92))
            g.addColorStop(1, Qt.rgba(Hud.HudStyle.ground.r, Hud.HudStyle.ground.g,
                                      Hud.HudStyle.ground.b, 0.96))
            ctx.fillStyle = g
            ctx.fill()

            // Faint grid, clipped to the panel shape.
            ctx.save()
            tracePath()
            ctx.clip()
            ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.07)
            ctx.lineWidth = 1
            var step = Hud.HudStyle.gridStep
            ctx.beginPath()
            for (var x = step; x < width; x += step) {
                ctx.moveTo(x + 0.5, 0)
                ctx.lineTo(x + 0.5, height)
            }
            for (var y = step; y < height; y += step) {
                ctx.moveTo(0, y + 0.5)
                ctx.lineTo(width, y + 0.5)
            }
            ctx.stroke()
            ctx.restore()

            // Glow border: an accent stroke with a soft shadow of the same hue.
            tracePath()
            if (glowIntensity > 0) {
                ctx.shadowColor = Qt.rgba(accent.r, accent.g, accent.b, glowIntensity)
                ctx.shadowBlur = 6 + glowIntensity * 10
            }
            ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.85)
            ctx.lineWidth = bw
            ctx.stroke()
        }
    }

    Item {
        id: contentHolder
        anchors.fill: parent
        anchors.margins: frame.contentPadding
    }
}
