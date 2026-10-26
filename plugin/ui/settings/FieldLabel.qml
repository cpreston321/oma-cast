import QtQuick
import qs.Commons

Text {
  property var look: null
  textFormat: Text.PlainText
  color: look.muted
  font.family: look.fontFamily
  font.pixelSize: Style.font.caption
  font.weight: Font.DemiBold
}
