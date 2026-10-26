import QtQuick
import QtQuick.Controls
import qs.Commons

// A scrolling column of SettingRows.
Flickable {
  id: form

  default property alias rows: column.data

  anchors.fill: parent
  contentWidth: width
  contentHeight: column.implicitHeight
  boundsBehavior: Flickable.StopAtBounds
  clip: true
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  Column {
    id: column
    width: form.width - Style.space(12)
  }
}
