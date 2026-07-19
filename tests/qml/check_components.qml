import QtQuick
import "../../package/contents/ui" as UI
import "../../package/contents/ui/hud" as Hud

// Runtime load smoke test: instantiate every HUD component with representative
// data and exit non-zero if any fails to construct. Catches property typos and
// binding errors that qmllint's syntax pass misses.
//   QT_QPA_PLATFORM=offscreen qml6 tests/qml/check_components.qml
Item {
    width: 400; height: 300

    Hud.HudFrame {
        anchors.fill: parent
        accent: Hud.HudStyle.accentFor(61, -95)
        glowIntensity: 0.6

        Column {
            UI.MetricBar { width: 300; label: "RSRP"; unit: "dBm"; value: -95; rangeLo: -125; rangeHi: -75 }
            UI.MetricBar { width: 300; label: "QUAL"; unit: "%"; value: null; rangeLo: 0; rangeHi: 100 }
            UI.KvRow { width: 300; key: "Band"; value: "B12" }
            UI.Bars { width: 60; height: 30; rsrp: -95 }
            UI.Sparkline { width: 120; height: 40; samples: [-96, -95, -94, -95] }
            UI.TowerModule { distanceM: 2188 }
            UI.TowerModule { distanceM: null }
            UI.NeighborList {
                width: 300
                neighbors: [{ band: "B2", earfcn: 700, rsrp_dbm: -105, rsrq_db: -15 }]
            }
        }
    }

    Component.onCompleted: {
        console.log("COMPONENTS_OK")
        Qt.exit(0)
    }
}
