import QtQuick
import qs.Commons
import qs.Ui

// The built-in calculator's preferences (config.json) and its history.
SettingsPage {
  id: page

  required property var backend
  required property var host

  title: "Calculator"
  description: "Type a calculation in the root search: units, currencies, dates, time zones, bases and percentages."

  readonly property var currencies: {
    page.backend.calculatorRevision
    var r = page.backend.callSync("calculator.getCurrencies", null)
    return r.ok ? r.data : ({})
  }
  readonly property int historyCount: {
    page.backend.storeRevision
    var r = page.backend.callSync("calculator.historyGetAll", null)
    return r.ok ? r.data.length : 0
  }
  property bool confirmClear: false

  function setConfig(patch) {
    var r = page.backend.callSync("settings.updateConfig", patch)
    if (!r.ok) page.host.flash(r.error, true)
  }

  SettingsForm {
    SettingRow {
      look: page.look
      label: "Currency conversion"
      description: page.backend.config.currencyRates
        ? (page.currencies.date ? "Daily ECB rates from frankfurter.dev, last " + page.currencies.date + " (" + page.currencies.currencies.length + " currencies)." : "Daily ECB rates from frankfurter.dev, not fetched yet.")
        : "Off: oma-cast makes no network requests."
      Row {
        spacing: Style.space(10)
        Button {
          visible: !!page.backend.config.currencyRates
          text: "Refresh"
          bordered: true
          onClicked: {
            var r = page.backend.callSync("calculator.refreshCurrencies", null)
            page.host.flash(r.ok ? "Fetching exchange rates…" : r.error, !r.ok)
          }
        }
        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: !!page.backend.config.currencyRates
          onToggled: page.setConfig({ currencyRates: !page.backend.config.currencyRates })
        }
      }
    }
    SettingRow {
      look: page.look
      label: "Clock format"
      description: "For times and time zone conversions. Automatic follows your locale."
      ButtonGroup {
        options: [{ value: "auto", label: "Automatic" }, { value: "12h", label: "12-hour" }, { value: "24h", label: "24-hour" }]
        value: page.backend.config.clockFormat || "auto"
        onChanged: function(v) { page.setConfig({ clockFormat: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Root em size (px)"
      description: "What 1 rem is in px ↔ rem conversions."
      NumberField {
        from: 1
        to: 128
        value: page.backend.config.remToPxRate || 16
        onModified: function(v) { page.setConfig({ remToPxRate: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Hours in a work day"
      description: "For conversions such as 40 hours in work days."
      NumberField {
        from: 1
        to: 24
        value: page.backend.config.workHoursPerDay || 8
        onModified: function(v) { page.setConfig({ workHoursPerDay: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Calculator History"
      description: page.historyCount === 0 ? "No saved calculations." : page.historyCount + (page.historyCount === 1 ? " saved calculation." : " saved calculations.")
      Button {
        enabled: page.historyCount > 0
        text: page.confirmClear ? "Click again to clear" : "Clear History"
        bordered: true
        onClicked: {
          if (!page.confirmClear) { page.confirmClear = true; confirmTimer.restart(); return }
          page.confirmClear = false
          var r = page.backend.callSync("calculator.historyDeleteAll", null)
          page.host.flash(r.ok ? "Calculator History cleared" : r.error, !r.ok)
        }
      }
    }
  }

  Timer { id: confirmTimer; interval: 3000; onTriggered: page.confirmClear = false }
}
