import QtQuick
import qs.Commons

// A label and description on the left, its control on the right.
Item {
  id: row

  property string label: ""
  property string description: ""
  property var look: null
  default property alias control: slot.data

  width: parent ? parent.width : 0
  height: Math.max(texts.implicitHeight, slot.childrenRect.height) + Style.space(24)

  Column {
    id: texts
    anchors.left: parent.left
    anchors.right: slot.left
    anchors.rightMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.label
      color: row.look.foreground
      wrapMode: Text.Wrap
      font.family: row.look.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      width: parent.width
      visible: text.length > 0
      textFormat: Text.PlainText
      text: row.description
      color: row.look.muted
      wrapMode: Text.Wrap
      font.family: row.look.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Util.alpha(row.look.foreground, 0.08)
  }
}
