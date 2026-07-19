import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_feedCommand: feedCommand.text
    property alias cfg_pollInterval: pollInterval.value
    property alias cfg_showBars: showBars.checked
    property alias cfg_showSparkline: showSparkline.checked
    property alias cfg_showBand: showBand.checked
    property alias cfg_showFrequency: showFrequency.checked
    property alias cfg_showTech: showTech.checked
    property alias cfg_showRsrp: showRsrp.checked
    property alias cfg_showRsrq: showRsrq.checked
    property alias cfg_showSnr: showSnr.checked
    property alias cfg_showRssi: showRssi.checked
    property alias cfg_showBandwidth: showBandwidth.checked
    property alias cfg_showAggregation: showAggregation.checked
    property alias cfg_showNeighbors: showNeighbors.checked
    property alias cfg_showDistance: showDistance.checked
    property alias cfg_showRrc: showRrc.checked
    property alias cfg_sparklineWindow: sparklineWindow.value
    property alias cfg_glowIntensity: glowIntensity.value
    property alias cfg_fixedAccent: fixedAccent.checked
    property string cfg_sparklineMetric
    property string cfg_fixedAccentColor

    onCfg_sparklineMetricChanged: {
        var i = sparklineMetric.indexOfValue(cfg_sparklineMetric)
        if (i >= 0) {
            sparklineMetric.currentIndex = i
        } else {
            // Unknown stored value (hand-edited config, downgrade): fall back
            // to the first metric and sync the config to it.
            sparklineMetric.currentIndex = 0
            cfg_sparklineMetric = sparklineMetric.valueAt(0)
        }
    }
    onCfg_fixedAccentColorChanged: {
        var i = fixedAccentColor.indexOfValue(cfg_fixedAccentColor)
        if (i >= 0) {
            fixedAccentColor.currentIndex = i
        } else {
            fixedAccentColor.currentIndex = 0
            cfg_fixedAccentColor = fixedAccentColor.valueAt(0)
        }
    }

    QQC2.TextField {
        id: feedCommand
        Kirigami.FormData.label: i18n("Feed command:")
        Layout.fillWidth: true
    }
    QQC2.SpinBox {
        id: pollInterval
        Kirigami.FormData.label: i18n("Poll interval (s):")
        from: 1; to: 30
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Panel") }
    QQC2.CheckBox { id: showBars; text: i18n("Signal bars") }
    QQC2.CheckBox { id: showSparkline; text: i18n("Live sparkline") }
    QQC2.CheckBox { id: showBand; text: i18n("Band (e.g. B12)") }
    QQC2.CheckBox { id: showFrequency; text: i18n("Frequency (MHz)") }
    QQC2.CheckBox { id: showTech; text: i18n("Technology (LTE/5G)") }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Metrics (popup)") }
    QQC2.CheckBox { id: showRsrp; text: "RSRP" }
    QQC2.CheckBox { id: showRsrq; text: "RSRQ" }
    QQC2.CheckBox { id: showSnr; text: "SNR" }
    QQC2.CheckBox { id: showRssi; text: "RSSI" }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Cell details (popup)") }
    QQC2.CheckBox { id: showBandwidth; text: i18n("Channel bandwidth") }
    QQC2.CheckBox { id: showAggregation; text: i18n("Carrier aggregation") }
    QQC2.CheckBox { id: showNeighbors; text: i18n("Neighbour cells") }
    QQC2.CheckBox { id: showDistance; text: i18n("Distance to tower") }
    QQC2.CheckBox { id: showRrc; text: i18n("RRC connection state") }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Sparkline") }
    QQC2.ComboBox {
        id: sparklineMetric
        Kirigami.FormData.label: i18n("Metric:")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: "RSRP", value: "rsrp_dbm" },
            { text: "RSRQ", value: "rsrq_db" },
            { text: "SNR", value: "snr_db" }
        ]
        onActivated: page.cfg_sparklineMetric = currentValue
    }
    QQC2.SpinBox {
        id: sparklineWindow
        Kirigami.FormData.label: i18n("History (samples):")
        from: 10; to: 600
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("HUD appearance") }
    QQC2.CheckBox {
        id: fixedAccent
        text: i18n("Fixed accent colour (ignore signal quality)")
    }
    QQC2.ComboBox {
        id: fixedAccentColor
        Kirigami.FormData.label: i18n("Accent:")
        enabled: fixedAccent.checked
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("Cyan-green"), value: "#29e7cd" },
            { text: i18n("Amber"), value: "#ffb020" },
            { text: i18n("Magenta"), value: "#ff3b8b" },
            { text: i18n("Ice blue"), value: "#3aa6ff" },
            { text: i18n("Lime"), value: "#8bff3b" }
        ]
        onActivated: page.cfg_fixedAccentColor = currentValue
    }
    QQC2.SpinBox {
        id: glowIntensity
        Kirigami.FormData.label: i18n("Glow intensity (%):")
        from: 0; to: 100; stepSize: 10
    }
}
