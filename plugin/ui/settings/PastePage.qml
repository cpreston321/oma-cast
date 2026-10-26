import QtQuick
import qs.Commons
import qs.Ui

// What ↵ does where there is a paste/copy choice, and the clipboard and
// emoji lists' sizes.
SettingsPage {
  id: page

  required property var backend
  required property var host

  title: "Paste & Copy"
  description: "What ↵ does, and how much the clipboard and emoji lists show. The other choice is always on Ctrl ↵. A click, or a hotkey, does what ↵ does."

  readonly property var general: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({})
  }
  readonly property var choices: [{ value: "paste", label: "Paste" }, { value: "copy", label: "Copy" }]

  function setGeneral(patch) {
    var r = page.backend.callSync("settings.updateGeneralSettings", patch)
    if (!r.ok) page.host.flash(r.error, true)
  }

  SettingsForm {
    SettingRow {
      look: page.look
      label: "Clipboard History"
      description: "Paste types the entry into the window you came from."
      ButtonGroup { options: page.choices; value: page.general.clipboardPrimary || "paste"; onChanged: function(v) { page.setGeneral({ clipboardPrimary: v }) } }
    }
    SettingRow {
      look: page.look
      label: "Emoji"
      ButtonGroup { options: page.choices; value: page.general.emojiPrimary || "paste"; onChanged: function(v) { page.setGeneral({ emojiPrimary: v }) } }
    }
    SettingRow {
      look: page.look
      label: "Snippets"
      description: "Paste also puts the caret at {cursor}."
      ButtonGroup { options: page.choices; value: page.general.snippetPrimary || "paste"; onChanged: function(v) { page.setGeneral({ snippetPrimary: v }) } }
    }
    SettingRow {
      look: page.look
      label: "Calculator answers"
      ButtonGroup { options: page.choices; value: page.general.calculatorPrimary || "copy"; onChanged: function(v) { page.setGeneral({ calculatorPrimary: v }) } }
    }
    SettingRow {
      look: page.look
      label: "Clipboard entries shown"
      description: "Omarchy decides how many it keeps; this is how many the list shows."
      NumberField {
        from: 10
        to: 500
        stepSize: 10
        value: page.general.clipboardRows || 100
        onModified: function(v) { page.setGeneral({ clipboardRows: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Frequently Used emoji"
      description: "How many of your most-used emoji lead the grid. 0 hides the row."
      NumberField {
        from: 0
        to: 64
        value: page.general.emojiFrequentCount === undefined ? 16 : page.general.emojiFrequentCount
        onModified: function(v) { page.setGeneral({ emojiFrequentCount: v }) }
      }
    }
  }
}
