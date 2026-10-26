import QtQuick
import qs.Commons
import "CommandRows.js" as CommandRows

// One extension on the Extensions page: its commands (alias, hotkey, on/off)
// first, then its own settings cards.
Item {
  id: pane

  property string extensionId: ""
  property string title: ""
  property string description: ""
  property string glyph: ""
  property var commandIds: []
  property var backend: null
  property var host: null
  property var look: null
  default property alias content: form.rows

  readonly property var commandRows: {
    pane.backend.storeRevision
    pane.backend.candidatesRevision
    var r = pane.backend.ready ? pane.backend.callSync("settings.getAllCommandSettings", null) : null
    return CommandRows.build(pane.backend.candidates, r && r.ok ? r.data : ({}), { ids: pane.commandIds })
  }

  Column {
    id: heading
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: pane.title
      color: pane.look.foreground
      font.family: pane.look.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }
    Text {
      width: parent.width
      visible: text.length > 0
      textFormat: Text.PlainText
      text: pane.description
      color: pane.look.muted
      wrapMode: Text.Wrap
      font.family: pane.look.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heading.bottom
    anchors.topMargin: Style.space(16)
    anchors.bottom: parent.bottom

    SettingsForm {
      id: form

      SettingsCard {
        look: pane.look
        title: pane.commandRows.length === 1 ? "Command" : "Commands"
        visible: pane.commandRows.length > 0
        Repeater {
          model: pane.commandRows
          CommandRow {
            required property int index
            backend: pane.backend
            host: pane.host
            look: pane.look
            divider: index < pane.commandRows.length - 1
          }
        }
      }
    }
  }
}
