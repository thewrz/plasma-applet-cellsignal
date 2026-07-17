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

    readonly property int pollInterval: Math.max(1, plasmoid.configuration.pollInterval)
    readonly property bool connected: feed !== null && feed.state === "connected" && !stale

    toolTipMainText: i18n("Cell Signal")
    toolTipSubText: {
        if (!feed) return i18n("no feed")
        if (feed.state !== "connected") return feed.state
        var parts = []
        if (feed.metrics.rsrp_dbm !== null) parts.push("RSRP " + feed.metrics.rsrp_dbm.toFixed(0) + " dBm")
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
        if (!doc || doc.version !== 1) {
            stale = true
            return
        }
        feed = doc
        var ageSecs = (Date.now() / 1000) - doc.ts
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
            root.handleOutput(data.stdout, data["exit code"])
        }
    }

    Timer {
        interval: root.pollInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: executable.connectSource(plasmoid.configuration.feedCommand)
    }
}
