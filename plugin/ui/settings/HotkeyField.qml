import QtQuick
import qs.Commons
import "../../core/Hotkeys.js" as Hotkeys

// Click, then press a hotkey. While recording, the host puts Hyprland in an
// empty submap so combos it already binds (Super+Space…) reach this field.
// Esc cancels, Backspace or Delete clears. `changed("")` removes the hotkey.
Rectangle {
  id: field

  property string value: ""
  property var host: null
  property var look: null
  property string placeholder: "Record hotkey"
  property string held: ""

  signal changed(string hotkey)

  readonly property bool recording: field.host && field.host.recordingField === field

  width: Style.space(150)
  height: Style.space(30)
  radius: Style.cornerRadius
  color: field.recording ? Util.alpha(field.look.accent, 0.15) : Util.alpha(field.look.foreground, mouse.containsMouse ? 0.08 : 0.04)
  border.width: 1
  border.color: field.recording ? field.look.accent : Util.alpha(field.look.foreground, 0.15)

  onRecordingChanged: { field.held = ""; if (field.recording) field.forceActiveFocus() }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: clear.visible ? clear.left : parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: field.recording ? (field.held || "Press keys…") : (field.value ? Hotkeys.display(field.value) : field.placeholder)
    color: field.look.foreground
    opacity: field.recording || field.value ? 1 : 0.5
    elide: Text.ElideRight
    font.family: field.look.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: clear
    visible: !!field.value && !field.recording
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: "×"
    color: field.look.foreground
    opacity: clearMouse.containsMouse ? 1 : 0.5
    font.pixelSize: Style.font.body

    MouseArea {
      id: clearMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: field.changed("")
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.rightMargin: clear.visible ? Style.space(24) : 0
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: field.recording ? field.host.stopRecording() : field.host.startRecording(field)
  }

  // Claim every key while recording, before the window's own shortcuts.
  Keys.onShortcutOverride: function(event) { event.accepted = field.recording }
  Keys.onPressed: function(event) {
    if (!field.recording) return
    event.accepted = true
    var bare = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)) === 0
    if (bare && event.key === Qt.Key_Escape) { field.host.stopRecording(); return }
    if (bare && (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)) { field.host.stopRecording(); field.changed(""); return }
    var r = Hotkeys.fromQt(event.key, event.modifiers)
    if (r.pending) {
      var mods = []
      if (event.modifiers & Qt.MetaModifier) mods.push("Super")
      if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl")
      if (event.modifiers & Qt.AltModifier) mods.push("Alt")
      if (event.modifiers & Qt.ShiftModifier) mods.push("Shift")
      field.held = mods.join(" ") + " …"
      return
    }
    if (r.error) { field.host.flash(r.error, true); return }
    field.host.stopRecording()
    field.changed(r.hotkey)
  }
}
