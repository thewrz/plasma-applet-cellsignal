import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "hud" as Hud

PlasmoidItem {
    id: root

    // Parsed contract doc (or null before first read / on parse failure)
    property var feed: null
    // Feed considered stale when older than 3 poll intervals or command failed
    property bool stale: true
    // Sparkline ring buffer of the configured metric
    property var history: []
    // Watchdog: wall-clock ms of the last feed reply (0 = none yet)
    property double lastDataMs: 0
    // Last band seen while connected — shown when a single tick reports band null
    // (the feeder's EARFCN agreement check fails by design mid-handover)
    property string lastBand: ""

    readonly property int pollInterval: Math.max(1, plasmoid.configuration.pollInterval)
    // Staleness threshold with a floor: feeder ticks land every ~2.5-3s and a
    // skipped tick (modem-lock contention) or slow RPC session pushes feed age
    // past a bare 3x poll interval — the floor keeps normal jitter from
    // flickering the panel into the dimmed state
    readonly property int staleAfterSecs: Math.max(pollInterval * 3, 12)
    // Single source of truth for the history bound: the config page exposes 10-600,
    // but hand-edited appletsrc values bypass the SpinBox — clamp at use time too
    readonly property int sparklineWindow: Math.min(600, Math.max(10, plasmoid.configuration.sparklineWindow))
    readonly property bool connected: feed !== null && feed.state === "connected" && !stale

    // Motion gate: Kirigami scales animation durations with the platform's
    // "Animation speed" setting, collapsing to 1ms when the user disables
    // animations. Every HUD animation checks this before running/easing.
    readonly property bool animationsEnabled: Kirigami.Units.longDuration > 1
    // 0..1 glow strength for HudFrame, from the config percentage.
    readonly property real glowIntensity: Math.max(0, Math.min(100, plasmoid.configuration.glowIntensity)) / 100

    // Signal-reactive HUD accent. The whole widget re-tints from this single
    // binding; a config switch pins a fixed accent instead. The Behavior below
    // gives every consumer one smooth cross-fade on change.
    readonly property color accentColor: {
        if (plasmoid.configuration.fixedAccent)
            return plasmoid.configuration.fixedAccentColor
        if (!connected)
            return Hud.HudStyle.accentIdle
        var q = (feed && typeof feed.quality_pct === "number") ? feed.quality_pct : null
        var r = (feed && feed.metrics && typeof feed.metrics.rsrp_dbm === "number")
                ? feed.metrics.rsrp_dbm : null
        return Hud.HudStyle.accentFor(q, r)
    }
    Behavior on accentColor {
        enabled: root.animationsEnabled
        ColorAnimation { duration: Kirigami.Units.longDuration }
    }

    toolTipMainText: i18n("Cell Signal")
    toolTipSubText: {
        if (!feed) return i18n("no feed")
        if (feed.state !== "connected") return feed.state
        var m = feed.metrics
        var parts = []
        if (plasmoid.configuration.showRsrp && typeof m.rsrp_dbm === "number")
            parts.push("RSRP " + m.rsrp_dbm.toFixed(0) + " dBm")
        if (plasmoid.configuration.showRsrq && typeof m.rsrq_db === "number")
            parts.push("RSRQ " + m.rsrq_db.toFixed(1) + " dB")
        if (plasmoid.configuration.showSnr && typeof m.snr_db === "number")
            parts.push("SNR " + m.snr_db.toFixed(1) + " dB")
        if (plasmoid.configuration.showRssi && typeof m.rssi_dbm === "number")
            parts.push("RSSI " + m.rssi_dbm.toFixed(0) + " dBm")
        var cellBits = []
        var band = feed.cell.band || lastBand
        if (band) cellBits.push(band)
        if (typeof feed.cell.freq_mhz === "number") cellBits.push(feed.cell.freq_mhz + " MHz")
        if (feed.tech) cellBits.push(feed.tech.toUpperCase())
        if (cellBits.length) parts.push(cellBits.join(" "))
        return parts.join(" · ") + (stale ? i18n(" (stale)") : "")
    }

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 10
    compactRepresentation: CompactRep {}
    fullRepresentation: FullRep {}

    function metricValue(doc, name) {
        if (!doc || !doc.metrics) return null
        var v = doc.metrics[name]
        return (v === undefined) ? null : v
    }

    // Contract: metrics are number-or-null, never strings or other types
    function validMetric(value) {
        return value === null || (typeof value === "number" && isFinite(value))
    }

    function handleOutput(stdout, exitCode) {
        if (exitCode !== 0 || !stdout || stdout.trim().length === 0) {
            stale = true
            return
        }
        var doc
        try {
            doc = JSON.parse(stdout)
        } catch (e) {
            stale = true
            return
        }
        if (!doc || [1, 2].indexOf(doc.version) < 0
                || typeof doc.ts !== "number" || !isFinite(doc.ts)
                || ["connected", "disconnected", "no-modem", "error"].indexOf(doc.state) < 0
                || typeof doc.metrics !== "object" || doc.metrics === null
                || typeof doc.cell !== "object" || doc.cell === null
                || !validMetric(doc.metrics.rsrp_dbm)
                || !validMetric(doc.metrics.rsrq_db)
                || !validMetric(doc.metrics.snr_db)
                || !validMetric(doc.metrics.rssi_dbm)) {
            stale = true
            return
        }
        feed = doc
        var ageSecs = (Date.now() / 1000) - doc.ts
        stale = ageSecs > staleAfterSecs
        if (doc.state === "connected") {
            if (doc.cell.band) lastBand = doc.cell.band
        } else {
            lastBand = ""
        }
        var v = metricValue(doc, plasmoid.configuration.sparklineMetric)
        if (doc.state === "connected" && typeof v === "number" && isFinite(v) && !stale) {
            var h = history.slice()
            h.push(v)
            while (h.length > root.sparklineWindow) h.shift()
            history = h
        }
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            // A slow reply from a superseded command must not overwrite fresh data
            if (source !== plasmoid.configuration.feedCommand) return
            root.lastDataMs = Date.now()
            root.handleOutput(data.stdout, data["exit code"])
        }

        function dropAllSources() {
            while (connectedSources.length > 0)
                disconnectSource(connectedSources[0])
        }
    }

    Connections {
        target: plasmoid.configuration
        function onSparklineMetricChanged() {
            // Samples of the old metric are a different unit/scale
            root.history = []
        }
        function onFeedCommandChanged() {
            // A new feed source's samples are discontinuous with the old one's,
            // and the old source's metrics must not present as live while the
            // new command has yet to answer (or hangs)
            root.history = []
            root.stale = true
            root.lastBand = ""   // never leak a previous source's band
            executable.dropAllSources()
        }
        function onSparklineWindowChanged() {
            if (root.history.length > root.sparklineWindow)
                root.history = root.history.slice(root.history.length - root.sparklineWindow)
        }
    }

    Timer {
        interval: root.pollInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Watchdog: a feed command that never exits emits no newData, so
            // staleness must also be detected from the poll side.
            if (Date.now() - root.lastDataMs > root.staleAfterSecs * 1000)
                root.stale = true
            var cmd = plasmoid.configuration.feedCommand
            if (executable.connectedSources.indexOf(cmd) !== -1) {
                // Previous run is wedged; kill it so the next connect re-executes
                executable.disconnectSource(cmd)
                root.stale = true
            }
            executable.connectSource(cmd)
        }
    }
}
