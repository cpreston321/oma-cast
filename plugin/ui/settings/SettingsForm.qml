import QtQuick
import QtQuick.Controls
import qs.Commons

// A scrolling column of SettingsCards (or SettingRows).
Flickable {
  id: form

  default property alias rows: column.data

  anchors.fill: parent
  contentWidth: width
  contentHeight: column.implicitHeight + Style.space(12)
  boundsBehavior: Flickable.StopAtBounds
  clip: true
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  Column {
    id: column
    width: form.width - Style.space(12)
    spacing: Style.space(20)
  }
}
