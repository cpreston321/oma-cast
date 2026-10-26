import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// One command with its alias, hotkey and on/off switch (Commands, and the
// Commands card on each extension page). modelData from CommandRows.build.
Item {
  id: row
  required property var modelData
  property var backend: null
  property var host: null
  property var look: null
  property bool divider: true
  width: parent ? parent.width : 0
  height: Style.space(46)

  function update(patch) {
    var r = row.backend.callSync("settings.updateCommandSettings", patch)
    if (!r.ok) row.host.flash(r.error, true)
    return r.ok
  }

  Item {
    id: icon
    width: Style.space(22)
    height: Style.space(22)
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter

    Image {
      anchors.fill: parent
      visible: row.modelData.iconName.length > 0 && row.modelData.glyph.length === 0
      source: visible ? Quickshell.iconPath(row.modelData.iconName, "application-x-executable") : ""
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }
    Text {
      anchors.centerIn: parent
      visible: row.modelData.glyph.length > 0
      textFormat: Text.PlainText
      text: row.modelData.glyph
      color: row.look.foreground
      font.family: row.modelData.glyphFont || row.look.fontFamily
      font.pixelSize: Style.space(15)
    }
  }

  Column {
    anchors.left: icon.right
    anchors.leftMargin: Style.space(12)
    anchors.right: aliasField.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    opacity: row.modelData.disabled ? 0.45 : 1

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.modelData.title
      color: row.look.foreground
      elide: Text.ElideRight
      font.family: row.look.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      width: parent.width
      visible: text.length > 0
      textFormat: Text.PlainText
      text: row.modelData.subtitle
      color: row.look.muted
      elide: Text.ElideRight
      font.family: row.look.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  TextField {
    id: aliasField
    anchors.right: hotkeyField.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(110)
    placeholderText: "Add alias"
    text: row.modelData.alias
    font.family: row.look.fontFamily
    font.pixelSize: Style.font.bodySmall
    onEditingFinished: {
      if (text.trim().toLowerCase() === row.modelData.alias) return
      if (!row.update({ commandId: row.modelData.id, alias: text.trim() })) text = row.modelData.alias
      else row.host.flash(text.trim() ? "Alias “" + text.trim().toLowerCase() + "” saved" : "Alias removed", false)
    }
  }

  HotkeyField {
    id: hotkeyField
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(140)
    host: row.host
    look: row.look
    value: row.modelData.hotkey
    onChanged: function(hotkey) { row.host.assignHotkey(row.modelData.id, hotkey) }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: !row.modelData.disabled
    onToggled: row.update({ commandId: row.modelData.id, enabled: row.modelData.disabled })
  }

  Rectangle {
    visible: row.divider
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Util.alpha(row.look.foreground, 0.06)
  }
}
