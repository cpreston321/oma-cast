import QtQuick
import qs.Commons
import qs.Ui

// General settings (db/settings.json `general`) and the launcher's own
// config.json keys.
SettingsPage {
  id: page

  required property var backend
  required property var host

  title: "General"
  description: "How the launcher looks and behaves. Changes apply immediately."

  readonly property bool hotkeysLoaded: page.backend.hotkeysLoaded

  readonly property var general: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({})
  }

  function setGeneral(patch) {
    var r = page.backend.callSync("settings.updateGeneralSettings", patch)
    if (!r.ok) page.host.flash(r.error, true)
  }

  function setConfig(patch) {
    var r = page.backend.callSync("settings.updateConfig", patch)
    if (!r.ok) page.host.flash(r.error, true)
  }

  SettingsForm {
    SettingRow {
      look: page.look
      label: "Launcher hotkey"
      description: page.hotkeysLoaded ? "Opens and closes oma-cast. Click, then press the keys."
        : "Saved to ~/.config/hypr/oma-cast.lua, which Hyprland doesn't load yet: run oma-cast setup hyprland."
      HotkeyField {
        host: page.host
        look: page.look
        value: page.general.launcherHotkey || ""
        placeholder: "None"
        onChanged: function(hotkey) { page.host.assignHotkey("launcher", hotkey) }
      }
    }
    SettingRow {
      look: page.look
      label: "Open on"
      description: "Which monitor the launcher appears on."
      ButtonGroup {
        options: [{ value: "mouse-screen", label: "Under the mouse" }, { value: "focused-screen", label: "Focused monitor" }]
        value: page.general.windowPresentationMode || "mouse-screen"
        onChanged: function(v) { page.setGeneral({ windowPresentationMode: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Window mode"
      description: "Compact shows only the search bar until you start typing."
      ButtonGroup {
        options: [{ value: "expanded", label: "Expanded" }, { value: "compact", label: "Compact" }]
        value: page.general.windowMode || "expanded"
        onChanged: function(v) { page.setGeneral({ windowMode: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Favorites in compact mode"
      description: "In compact mode, show your favorites under the search bar."
      ToggleSwitch {
        checked: !!page.general.showFavoritesInCompactMode
        onToggled: page.setGeneral({ showFavoritesInCompactMode: !page.general.showFavoritesInCompactMode })
      }
    }
    SettingRow {
      look: page.look
      label: "Text size"
      description: "Also Ctrl + / Ctrl − / Ctrl 0 in the launcher."
      ButtonGroup {
        options: [{ value: "0.9", label: "90%" }, { value: "1", label: "100%" }, { value: "1.1", label: "110%" }, { value: "1.2", label: "120%" }, { value: "1.3", label: "130%" }]
        value: String(page.general.uiZoom || 1)
        onChanged: function(v) { page.setGeneral({ uiZoom: Number(v) }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Launcher size (px)"
      description: "Width × height at 100% text size. It never grows past the screen."
      Row {
        spacing: Style.space(8)
        NumberField {
          from: 500
          to: 3000
          stepSize: 25
          value: page.general.windowWidth || 750
          onModified: function(v) { page.setGeneral({ windowWidth: v }) }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "×"
          color: page.look.muted
          font.family: page.look.fontFamily
          font.pixelSize: Style.font.body
        }
        NumberField {
          from: 300
          to: 2000
          stepSize: 25
          value: page.general.windowHeight || 475
          onModified: function(v) { page.setGeneral({ windowHeight: v }) }
        }
      }
    }
    SettingRow {
      look: page.look
      label: "Escape key"
      description: "What Esc does once the search field is empty."
      Select {
        width: Style.space(240)
        showLabel: false
        options: [{ value: "pop-back-or-close", label: "Go back, then close" }, { value: "close-and-pop-to-root", label: "Close and return to root" }]
        value: page.general.escapeKeyBehavior || "pop-back-or-close"
        onChanged: function(v) { page.setGeneral({ escapeKeyBehavior: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Return to root after (seconds)"
      description: "Reopening within this time keeps your place. 0 always starts at root."
      NumberField {
        from: 0
        to: 3600
        stepSize: 15
        value: page.general.popToRootTimeout === undefined ? 90 : page.general.popToRootTimeout
        onModified: function(v) { page.setGeneral({ popToRootTimeout: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Navigation keys"
      description: "Vim moves with Ctrl+J/K and opens actions with Alt+K."
      ButtonGroup {
        options: [{ value: "emacs", label: "Emacs" }, { value: "vim-motions", label: "Vim" }]
        value: page.general.navigationBindings || "emacs"
        onChanged: function(v) { page.setGeneral({ navigationBindings: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Stay open when focus moves away"
      description: "Clicking outside the launcher leaves it open."
      ToggleSwitch {
        checked: !!page.backend.config.keepVisibleOnFocusLoss
        onToggled: page.setConfig({ keepVisibleOnFocusLoss: !page.backend.config.keepVisibleOnFocusLoss })
      }
    }
  }
}
