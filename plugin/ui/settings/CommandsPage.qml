import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// Every root-search command: its alias and whether it is enabled. The
// launcher can disable a command but not bring it back; this page can.
SettingsPage {
  id: page

  required property var backend
  required property var host
  property string filter: ""
  property string show: "all"

  title: "Commands"
  description: "Give anything an alias, or switch off what you never use. Typing an alias exactly puts its command first."

  readonly property var commands: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getAllCommandSettings", null) : null
    return r && r.ok ? r.data : ({})
  }

  readonly property var rows: {
    var q = page.filter.trim().toLowerCase()
    var settings = page.commands
    var out = []
    var list = page.backend.candidates
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      var s = settings[c.id] || {}
      var disabled = s.enabled === false
      if (page.show === "disabled" && !disabled) continue
      if (page.show === "aliased" && !s.alias) continue
      if (q && (c.title + " " + c.subtitle + " " + (s.alias || "")).toLowerCase().indexOf(q) < 0) continue
      out.push({ id: c.id, title: c.title, subtitle: c.subtitle || c.typeLabel || "", glyph: c.glyph || "", glyphFont: c.glyphFont || "", iconName: c.iconName || "", alias: s.alias || "", disabled: disabled })
    }
    out.sort(function(a, b) { return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : (a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0) })
    return out
  }

  function update(patch) {
    var r = page.backend.callSync("settings.updateCommandSettings", patch)
    if (!r.ok) page.host.flash(r.error, true)
    return r.ok
  }

  Row {
    id: toolbar
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(12)

    TextField {
      width: parent.width - showGroup.width - parent.spacing - Style.space(12)
      placeholderText: "Filter " + page.backend.candidates.length + " commands…"
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: page.filter = text
    }
    ButtonGroup {
      id: showGroup
      anchors.verticalCenter: parent.verticalCenter
      options: [{ value: "all", label: "All" }, { value: "aliased", label: "With alias" }, { value: "disabled", label: "Disabled" }]
      value: page.show
      onChanged: function(v) { page.show = v }
    }
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: toolbar.bottom
    anchors.topMargin: Style.space(10)
    anchors.bottom: parent.bottom
    clip: true
    model: page.rows
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    delegate: Item {
      id: entry
      required property var modelData
      width: list.width - Style.space(12)
      height: Style.space(46)

      Item {
        id: icon
        width: Style.space(22)
        height: Style.space(22)
        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter

        Image {
          anchors.fill: parent
          visible: entry.modelData.iconName.length > 0 && entry.modelData.glyph.length === 0
          source: visible ? Quickshell.iconPath(entry.modelData.iconName, "application-x-executable") : ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
        Text {
          anchors.centerIn: parent
          visible: entry.modelData.glyph.length > 0
          textFormat: Text.PlainText
          text: entry.modelData.glyph
          color: page.look.foreground
          font.family: entry.modelData.glyphFont || page.look.fontFamily
          font.pixelSize: Style.space(15)
        }
      }

      Column {
        anchors.left: icon.right
        anchors.leftMargin: Style.space(12)
        anchors.right: aliasField.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        opacity: entry.modelData.disabled ? 0.45 : 1

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: entry.modelData.title
          color: page.look.foreground
          elide: Text.ElideRight
          font.family: page.look.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          visible: text.length > 0
          textFormat: Text.PlainText
          text: entry.modelData.subtitle
          color: page.look.muted
          elide: Text.ElideRight
          font.family: page.look.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      TextField {
        id: aliasField
        anchors.right: toggle.left
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(130)
        placeholderText: "Add alias"
        text: entry.modelData.alias
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.bodySmall
        onEditingFinished: {
          if (text.trim().toLowerCase() === entry.modelData.alias) return
          if (!page.update({ commandId: entry.modelData.id, alias: text.trim() })) text = entry.modelData.alias
          else page.host.flash(text.trim() ? "Alias “" + text.trim().toLowerCase() + "” saved" : "Alias removed", false)
        }
      }

      ToggleSwitch {
        id: toggle
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: !entry.modelData.disabled
        onToggled: page.update({ commandId: entry.modelData.id, enabled: entry.modelData.disabled })
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Util.alpha(page.look.foreground, 0.06)
      }
    }

    Text {
      anchors.centerIn: parent
      visible: list.count === 0
      textFormat: Text.PlainText
      text: page.show === "disabled" ? "Nothing is disabled" : "No commands match"
      color: page.look.muted
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
