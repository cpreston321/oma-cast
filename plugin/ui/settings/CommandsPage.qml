import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "CommandRows.js" as CommandRows

// Every root-search command: its alias and whether it is enabled. The
// launcher can disable a command but not bring it back; this page can.
SettingsPage {
  id: page

  required property var backend
  required property var host
  property string filter: ""
  property string show: "all"

  tabId: "commands"
  title: "Commands"
  description: "Give anything an alias or a hotkey, or switch off what you never use. Typing an alias exactly puts its command first; a hotkey runs it from anywhere."

  readonly property var commands: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getAllCommandSettings", null) : null
    return r && r.ok ? r.data : ({})
  }

  readonly property var rows: CommandRows.build(page.backend.candidates, page.commands, { show: page.show, query: page.filter })

  Row {
    id: toolbar
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(12)

    TextField {
      width: parent.width - showGroup.width - parent.spacing - Style.space(12)
      placeholderText: "Filter commands…"
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: page.filter = text
    }
    ButtonGroup {
      id: showGroup
      anchors.verticalCenter: parent.verticalCenter
      options: [{ value: "all", label: "All" }, { value: "aliased", label: "Aliases" }, { value: "hotkeys", label: "Hotkeys" }, { value: "disabled", label: "Disabled" }]
      value: page.show
      onChanged: function(v) { page.show = v }
    }
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: toolbar.bottom
    anchors.topMargin: Style.space(10)
    anchors.bottom: parent.bottom
    clip: true
    model: page.rows
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    delegate: CommandRow {
      required property int index
      width: list.width - Style.space(12)
      backend: page.backend
      host: page.host
      look: page.look
      divider: index < list.count - 1
    }

    Text {
      anchors.centerIn: parent
      visible: list.count === 0
      textFormat: Text.PlainText
      text: page.show === "disabled" ? "Nothing is disabled" : (page.show === "hotkeys" ? "No hotkeys yet" : "No commands match")
      color: page.look.muted
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
