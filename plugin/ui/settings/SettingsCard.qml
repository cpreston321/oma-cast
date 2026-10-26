import QtQuick
import qs.Commons

// A titled group of SettingRows (or anything else) on a rounded panel. An
// advanced card shows only with "Show advanced" on.
Column {
  id: card

  property string title: ""
  property string note: ""
  property bool advanced: false
  property var look: null
  default property alias rows: inner.data
  // Optional control beside the title (a Refresh button…).
  property alias trailing: trailingSlot.data
  readonly property bool isSettingsCard: true

  visible: !card.advanced || !!(card.look && card.look.advanced)
  width: parent ? parent.width : 0
  spacing: Style.space(6)

  Item {
    width: parent.width
    height: Math.max(heading.implicitHeight, trailingSlot.childrenRect.height)
    visible: card.title.length > 0

    Text {
      id: heading
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      textFormat: Text.PlainText
      text: card.title.toUpperCase() + (card.advanced ? "  · ADVANCED" : "")
      color: card.look.muted
      font.family: card.look.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      font.letterSpacing: 0.5
    }
    Item {
      id: trailingSlot
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  Text {
    width: parent.width
    visible: card.note.length > 0
    textFormat: Text.PlainText
    text: card.note
    color: card.look.muted
    wrapMode: Text.Wrap
    font.family: card.look.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Rectangle {
    width: parent.width
    height: inner.implicitHeight + Style.space(8)
    radius: Style.cornerRadius * 1.5
    color: Util.alpha(card.look.foreground, 0.035)
    border.width: 1
    border.color: Util.alpha(card.look.foreground, 0.07)

    Column {
      id: inner
      x: Style.space(16)
      y: Style.space(4)
      width: parent.width - Style.space(32)
    }
  }
}
