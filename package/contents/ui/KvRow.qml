import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "hud" as Hud

// Key/value line for the popup's right column: dim mono key, bright mono value.
// The caller sets `visible` (typically false when the value is null) so the
// stack collapses cleanly around absent fields.
RowLayout {
    id: kvRow

    property string key
    property string value
    property color accent: Hud.HudStyle.accentGood

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    Text {
        text: kvRow.key
        color: Hud.HudStyle.textDim
        font.family: Hud.HudStyle.fontMono
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
    }
    Text {
        text: kvRow.value
        color: Hud.HudStyle.textBright
        font.family: Hud.HudStyle.fontMono
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        Layout.fillWidth: true
    }
}
