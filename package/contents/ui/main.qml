import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

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

    readonly property int pollInterval: Math.max(1, plasmoid.configuration.pollInterval)
    readonly property bool connected: feed !== null && feed.state === "connected" && !stale

    toolTipMainText: i18n("Cell Signal")
    toolTipSubText: {
        if (!feed) return i18n("no feed")
        if (feed.state !== "connected") return feed.state
        var parts = []
        if (typeof feed.metrics.rsrp_dbm === "number") parts.push("RSRP " + feed.metrics.rsrp_dbm.toFixed(0) + " dBm")
        if (feed.cell.band) parts.push(feed.cell.band)
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
        if (!doc || doc.version !== 1
                || typeof doc.metrics !== "object" || doc.metrics === null
                || typeof doc.cell !== "object" || doc.cell === null) {
            stale = true
            return
        }
        feed = doc
        var tsOk = typeof doc.ts === "number" && isFinite(doc.ts)
        var ageSecs = tsOk ? (Date.now() / 1000) - doc.ts : Infinity
        stale = ageSecs > pollInterval * 3
        var v = metricValue(doc, plasmoid.configuration.sparklineMetric)
        if (doc.state === "connected" && v !== null && !stale) {
            var h = history.slice()
            h.push(v)
            var max = Math.max(2, plasmoid.configuration.sparklineWindow)
            while (h.length > max) h.shift()
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
            executable.dropAllSources()
        }
        function onSparklineWindowChanged() {
            var max = Math.max(2, plasmoid.configuration.sparklineWindow)
            if (root.history.length > max)
                root.history = root.history.slice(root.history.length - max)
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
            if (Date.now() - root.lastDataMs > root.pollInterval * 3000)
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
