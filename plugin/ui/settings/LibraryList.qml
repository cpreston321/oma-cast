import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The left column of the Snippets and Quicklinks pages: the saved items,
// with New, Import and Export below. items: [{id, title, subtitle}].
Item {
  id: library

  property var items: []
  property string selectedId: ""
  property string emptyText: "Nothing saved yet"
  property var look: null

  signal picked(string id)
  signal createRequested()
  signal importRequested()
  signal exportRequested()

  Rectangle {
    anchors.fill: parent
    radius: Math.max(Style.cornerRadius, Style.space(6))
    color: Util.alpha(library.look.foreground, 0.03)
    border.width: 1
    border.color: Util.alpha(library.look.foreground, 0.08)
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: buttons.top
    anchors.margins: Style.space(6)
    clip: true
    model: library.items
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    delegate: Rectangle {
      id: entry
      required property var modelData
      width: list.width
      height: Style.space(44)
      radius: Math.max(Style.cornerRadius, Style.space(5))
      color: entry.modelData.id === library.selectedId ? Util.alpha(library.look.accent, 0.18)
        : (mouse.containsMouse ? Util.alpha(library.look.foreground, 0.05) : "transparent")

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: entry.modelData.title
          color: library.look.foreground
          elide: Text.ElideRight
          font.family: library.look.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          visible: text.length > 0
          textFormat: Text.PlainText
          text: entry.modelData.subtitle
          color: library.look.muted
          elide: Text.ElideRight
          font.family: library.look.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: library.picked(entry.modelData.id)
      }
    }

    Text {
      anchors.centerIn: parent
      visible: list.count === 0
      textFormat: Text.PlainText
      text: library.emptyText
      color: library.look.muted
      font.family: library.look.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Row {
    id: buttons
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    Button { text: "New"; bordered: true; onClicked: library.createRequested() }
    Button { text: "Import"; tooltipText: "Import a JSON export from the clipboard"; onClicked: library.importRequested() }
    Button { text: "Export"; tooltipText: "Save to ~/Downloads and copy"; onClicked: library.exportRequested() }
  }
}
