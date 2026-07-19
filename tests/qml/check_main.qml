import QtQuick
import QtQuick.Window

// Load the actual applet entry point. Component-only smoke tests do not catch
// invalid root-level property declarations such as a Behavior targeting a
// read-only property.
Window {
    width: 640
    height: 480
    visible: false

    Loader {
        id: appletLoader
        anchors.fill: parent
        source: "../../package/contents/ui/main.qml"

        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("FAIL: applet root did not load")
                Qt.exit(1)
            }
            if (status === Loader.Ready) {
                console.log("MAIN_OK")
                Qt.exit(0)
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: {
            console.error("FAIL: applet root load timed out")
            Qt.exit(2)
        }
    }
}
