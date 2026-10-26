import QtQuick
import qs.Commons
import qs.Ui

// The Calculator extension: its preferences (config.json), ↵, and history.
ExtensionPane {
  id: page

  property string primary: "copy"
  signal primaryChosen(string value)

  title: "Calculator"
  commandIds: ["builtin:calculator-history"]
  description: "Type a calculation in the root search: units, currencies, dates, time zones, bases and percentages. An amount on its own converts too: “16rem”, “5 kg”, “€50”."

  readonly property var currencies: {
    page.backend.calculatorRevision
    page.backend.config
    var r = page.backend.callSync("calculator.getCurrencies", null)
    return r.ok ? r.data : ({})
  }
  readonly property int historyCount: {
    page.backend.storeRevision
    var r = page.backend.callSync("calculator.historyGetAll", null)
    return r.ok ? r.data.length : 0
  }
  property bool confirmClear: false
  readonly property var systemNames: ({ us: "US customary", uk: "UK imperial", metric: "Metric" })

  // Each unit a lone amount converts (Calculator.conversionOptions).
  readonly property var conversions: {
    page.backend.config
    var r = page.backend.callSync("calculator.conversionOptions", null)
    return r.ok ? r.data : []
  }
  readonly property int changedConversions: page.conversions.filter(function(c) { return c.changed }).length

  function labelFor(row, sym) {
    if (sym === "none") return "Don't convert"
    var c = row.choices.filter(function(x) { return x.value === sym })[0]
    return c ? c.label : sym
  }

  // "Automatic (US Dollar (USD))", then every currency with a rate.
  function currencyOptions(automatic) {
    var names = page.currencies.names || ({})
    var codes = Object.keys(names).sort(function(a, b) { return names[a] < names[b] ? -1 : 1 })
    return [{ value: "auto", label: "Automatic" + (automatic ? " (" + (names[automatic] || automatic) + ")" : "") }]
      .concat(codes.map(function(c) { return { value: c, label: names[c] } }))
  }

  function setConfig(patch) {
    var r = page.backend.callSync("settings.updateConfig", patch)
    if (!r.ok) page.host.flash(r.error, true)
  }

  SettingsCard {
    look: page.look
    title: "Behaviour"
    SettingRow {
      look: page.look
      label: "↵ on an answer"
      description: "The other choice is on Ctrl ↵."
      keywords: "paste copy enter primary action"
      ButtonGroup {
        options: [{ value: "copy", label: "Copy" }, { value: "paste", label: "Paste" }]
        value: page.primary
        onChanged: function(v) { page.primaryChosen(v) }
      }
    }
  }
  SettingsCard {
    look: page.look
    title: "Currency"
      SettingRow {
        look: page.look
        keywords: "money exchange rates frankfurter network"
        label: "Currency conversion"
        description: page.backend.config.currencyRates
          ? (page.currencies.date ? "Daily rates from frankfurter.dev, last " + page.currencies.date + " (" + page.currencies.currencies.length + " currencies, Bitcoin and gold included)." : "Daily rates from frankfurter.dev, not fetched yet.")
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
        keywords: "home money dollar euro pound"
        label: "Your currency"
        description: "An amount on its own (“€50”, “100 cad”) converts to this. Automatic follows your locale (" + (page.currencies.locale || "") + ")."
        SearchSelect {
          width: Style.space(280)
          showLabel: false
          placeholderText: "Search currencies…"
          options: page.currencyOptions(page.currencies.home)
          value: page.backend.config.homeCurrency || "auto"
          onChanged: function(v) { page.setConfig({ homeCurrency: v }) }
        }
      }
      SettingRow {
        look: page.look
        keywords: "money exchange"
        label: "Second currency"
        description: "An amount already in your currency (“$100”) converts to this."
        SearchSelect {
          width: Style.space(280)
          showLabel: false
          placeholderText: "Search currencies…"
          options: page.currencyOptions(page.currencies.second)
          value: page.backend.config.secondCurrency || "auto"
          onChanged: function(v) { page.setConfig({ secondCurrency: v }) }
        }
      }
  }
  SettingsCard {
    look: page.look
    title: "Units"
      SettingRow {
        look: page.look
        keywords: "metric imperial us uk inches pounds"
        label: "Measurement system"
        description: "Sets the defaults below, and what “gal”, “pint” and “fl oz” mean (larger imperial measures in the UK). Automatic follows your locale (" + (page.currencies.locale || "") + ")."
        Select {
          width: Style.space(260)
          showLabel: false
          options: [
            { value: "auto", label: "Automatic (" + page.systemNames[page.currencies.localeMeasurement || "metric"] + ")" },
            { value: "us", label: page.systemNames.us },
            { value: "uk", label: page.systemNames.uk },
            { value: "metric", label: page.systemNames.metric }
          ]
          value: page.backend.config.measurementSystem || "auto"
          onChanged: function(v) { page.setConfig({ measurementSystem: v }) }
        }
      }
      SettingRow {
        look: page.look
        keywords: "rem css pixels"
        advanced: true
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
        keywords: "work days hours"
        advanced: true
        label: "Hours in a work day"
        description: "For conversions such as 40 hours in work days."
        NumberField {
          from: 1
          to: 24
          value: page.backend.config.workHoursPerDay || 8
          onModified: function(v) { page.setConfig({ workHoursPerDay: v }) }
        }
      }
  }
  SettingsCard {
    look: page.look
    title: "Time"
      SettingRow {
        look: page.look
        keywords: "12 24 hour am pm"
        label: "Clock format"
        description: "For times and time zone conversions. Automatic follows your locale."
        ButtonGroup {
          options: [{ value: "auto", label: "Automatic" }, { value: "12h", label: "12-hour" }, { value: "24h", label: "24-hour" }]
          value: page.backend.config.clockFormat || "auto"
          onChanged: function(v) { page.setConfig({ clockFormat: v }) }
        }
      }
  }
  SettingsCard {
    look: page.look
    title: "History"
      SettingRow {
        look: page.look
        keywords: "clear delete calculations"
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
  SettingsCard {
    look: page.look
    title: "When you type just an amount"
    note: "“16rem” or “5 kg” on its own converts to the unit below; the defaults follow your measurement system. Naming a target (“5 kg to g”) always wins."
    trailing: Button {
      visible: page.changedConversions > 0
      text: "Reset " + page.changedConversions + (page.changedConversions === 1 ? " change" : " changes")
      onClicked: {
        var r = page.backend.callSync("calculator.resetConversions", null)
        page.host.flash(r.ok ? "Conversions reset to the defaults" : r.error, !r.ok)
      }
    }
      Repeater {
        model: page.conversions

        Column {
          id: conversion
          required property var modelData
          required property int index
          width: parent ? parent.width : 0
          readonly property bool firstOfKind: conversion.index === 0 || page.conversions[conversion.index - 1].kind !== conversion.modelData.kind

          Text {
            visible: conversion.firstOfKind
            textFormat: Text.PlainText
            text: conversion.modelData.kind
            color: page.look.foreground
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            topPadding: Style.space(12)
            bottomPadding: Style.space(2)
          }
          SettingRow {
            look: page.look
            divider: conversion.index < page.conversions.length - 1 && page.conversions[conversion.index + 1].kind === conversion.modelData.kind
            keywords: "convert conversion default unit " + conversion.modelData.kind
            label: conversion.modelData.name + " (" + conversion.modelData.from + ")"
            description: conversion.modelData.changed ? "Default: " + page.labelFor(conversion.modelData, conversion.modelData.defaultTarget) : ""
            Select {
              width: Style.space(260)
              showLabel: false
              options: [{ value: "none", label: "Don't convert" }].concat(conversion.modelData.choices)
              value: conversion.modelData.target
              onChanged: function(v) {
                var r = page.backend.callSync("calculator.setConversion", { from: conversion.modelData.from, target: v })
                if (!r.ok) page.host.flash(r.error, true)
              }
            }
          }
        }
      }
  }

  Timer { id: confirmTimer; interval: 3000; onTriggered: page.confirmClear = false }
}
