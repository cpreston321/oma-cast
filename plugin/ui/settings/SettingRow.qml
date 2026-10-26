import QtQuick
import qs.Commons

// A label and description on the left, its control on the right. Settings
// search finds rows by label, description and keywords; an advanced row shows
// only with "Show advanced" on.
Item {
  id: row

  property string label: ""
  property string description: ""
  property string keywords: ""
  property bool advanced: false
  property var look: null
  default property alias control: slot.data
  readonly property bool isSettingRow: true
  // null: a divider unless last in its group; true/false forces it.
  property var divider: null
  // The divider only separates rows: none after the last row of a group
  // (the next shown item is a heading, a list or nothing).
  readonly property bool lastInGroup: {
    var kids = row.parent ? row.parent.children : []
    var after = false
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] === row) { after = true; continue }
      if (!after || !kids[i].visible || kids[i].height <= 0) continue
      return !kids[i].isSettingRow
    }
    return true
  }

  visible: !row.advanced || !!(row.look && row.look.advanced)
  width: parent ? parent.width : 0
  height: Math.max(texts.implicitHeight, slot.childrenRect.height) + Style.space(20)

  // Scrolls the row into view in its form and flashes it (settings search).
  function reveal() {
    for (var p = row.parent; p; p = p.parent) {
      if (p.contentItem !== undefined && p.contentY !== undefined && p.contentHeight !== undefined) {
        var y = row.mapToItem(p.contentItem, 0, 0).y
        p.contentY = Math.max(0, Math.min(y - Style.space(40), p.contentHeight - p.height))
        break
      }
    }
    highlight.opacity = 1
    fade.restart()
  }

  Rectangle {
    id: highlight
    anchors.fill: parent
    anchors.leftMargin: -Style.space(8)
    anchors.rightMargin: -Style.space(8)
    radius: Style.cornerRadius
    color: Util.alpha(row.look.accent, 0.16)
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 600 } }
    Timer { id: fade; interval: 1400; onTriggered: highlight.opacity = 0 }
  }

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
    visible: row.divider === null ? !row.lastInGroup : !!row.divider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Util.alpha(row.look.foreground, 0.08)
  }
}
