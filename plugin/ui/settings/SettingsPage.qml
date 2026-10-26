import QtQuick
import qs.Commons

// One Settings page: a title and description, then its content filling the
// rest. A form page scrolls its rows with SettingsForm.
Item {
  id: page

  property string title: ""
  // The sidebar tab it belongs to, for settings search.
  property string tabId: ""
  property string description: ""
  property var look: null
  default property alias content: body.data

  Column {
    id: heading
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(4)
    visible: page.title.length > 0
    height: visible ? implicitHeight : 0

    Text {
      textFormat: Text.PlainText
      text: page.title
      color: page.look.foreground
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }
    Text {
      width: parent.width
      visible: text.length > 0
      textFormat: Text.PlainText
      text: page.description
      color: page.look.muted
      wrapMode: Text.Wrap
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Item {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heading.bottom
    anchors.topMargin: heading.visible ? Style.space(16) : 0
    anchors.bottom: parent.bottom
  }
}
