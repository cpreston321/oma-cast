import QtQuick
import qs.Commons
import qs.Ui

// History and rankings, backups, and logging.
SettingsPage {
  id: page

  required property var backend
  required property var host

  title: "Data"
  tabId: "data"
  description: "oma-cast keeps everything in ~/.local/share/oma-cast and ~/.config/oma-cast, on this computer only."

  // The button waiting for its second click.
  property string confirming: ""
  Timer { id: confirmTimer; interval: 3000; onTriggered: page.confirming = "" }

  function twice(id, run) {
    if (page.confirming !== id) { page.confirming = id; confirmTimer.restart(); return }
    page.confirming = ""
    run()
  }

  function call(method, data, done) {
    var r = page.backend.callSync(method, data)
    if (!r.ok) { page.host.flash(r.error, true); return }
    if (r.data && r.data.title) page.host.flash(r.data.title, r.data.ok === false)
    else if (r.data && r.data.toast) page.host.flash(r.data.toast.title, r.data.toast.style === "failure")
    else if (done) page.host.flash(done, false)
  }

  SettingsForm {
    SettingsCard {
      look: page.look
      title: "History"
      SettingRow {
        look: page.look
        keywords: "clear recent queries"
        label: "Search history"
        description: "What ↑ recalls in an empty search."
        Button {
          text: page.confirming === "history" ? "Click again to clear" : "Clear"
          bordered: true
          onClicked: page.twice("history", function() { page.call("data.clearSearchHistory", null, "Search history cleared") })
        }
      }
      SettingRow {
        look: page.look
        keywords: "frecency reset"
        label: "Rankings"
        description: "What you open often rises to the top, and the terms you used to find it are remembered. Resetting starts that over; aliases and favorites stay."
        Button {
          text: page.confirming === "rankings" ? "Click again to reset" : "Reset All"
          bordered: true
          onClicked: page.twice("rankings", function() { page.call("data.resetRankings", null, "Rankings reset") })
        }
      }
      SettingRow {
        look: page.look
        keywords: "clear recent emoji"
        label: "Frequently Used emoji"
        Button {
          text: page.confirming === "emoji" ? "Click again to clear" : "Clear"
          bordered: true
          onClicked: page.twice("emoji", function() { page.call("data.clearEmojiRecents", null, "Frequently Used emoji cleared") })
        }
      }
    }
    SettingsCard {
      look: page.look
      title: "Backup"
      SettingRow {
        look: page.look
        keywords: "export save"
        label: "Back up"
        description: "Settings, aliases, hotkeys, favorites, snippets, quicklinks and emoji use in one file, saved to ~/Downloads and copied."
        Button { text: "Back Up"; bordered: true; onClicked: page.call("data.backup", null, "") }
      }
      SettingRow {
        look: page.look
        keywords: "import load"
        label: "Restore"
        description: "From a backup file, or a backup on the clipboard. Settings are replaced; snippets and quicklinks are added beside yours."
        Row {
          spacing: Style.space(8)
          TextField {
            id: restorePath
            width: Style.space(240)
            placeholderText: "~/Downloads/oma-cast-backup-….json"
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            text: page.confirming === "restore" ? "Click again to restore" : (restorePath.text.trim() ? "Restore File" : "From Clipboard")
            bordered: true
            onClicked: page.twice("restore", function() { page.call("data.restore", { path: restorePath.text }, "") })
          }
        }
      }
    }
    SettingsCard {
      look: page.look
      title: "Diagnostics"
      advanced: true
      SettingRow {
        look: page.look
        keywords: "debug logging"
        label: "Log level"
        description: "How much oma-cast writes to the shell log (qs log -p $OMARCHY_PATH/shell)."
        Select {
          width: Style.space(160)
          showLabel: false
          options: ["trace", "debug", "info", "warning", "error"]
          value: page.backend.config.logLevel || "info"
          onChanged: function(v) {
            var r = page.backend.callSync("settings.updateConfig", { logLevel: v })
            if (!r.ok) page.host.flash(r.error, true)
          }
        }
      }
    }
  }
}
