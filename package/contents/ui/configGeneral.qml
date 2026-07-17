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
    property alias cfg_sparklineWindow: sparklineWindow.value
    property string cfg_sparklineMetric
    onCfg_sparklineMetricChanged: {
        sparklineMetric.currentIndex = sparklineMetric.indexOfValue(cfg_sparklineMetric)
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
}
