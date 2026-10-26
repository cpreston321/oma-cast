import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "../../core/Hotkeys.js" as Hotkeys

// The Settings window (fork, SPEC §10.5): a normal Hyprland window with a
// sidebar of pages. open({tab, snippetId?, quicklinkId?}) shows it on a page,
// optionally with an item open in its editor ("new" for a fresh one).
FloatingWindow {
  id: win

  required property var backend

  property string tab: "general"
  property string message: ""
  property bool messageIsError: false

  title: "oma-cast Settings"
  color: Commons.Color.background
  implicitWidth: 1060
  implicitHeight: 680
  minimumSize: Qt.size(880, 540)
  visible: false

  readonly property var look: ({
    background: Commons.Color.background,
    foreground: Commons.Color.foreground,
    accent: Commons.Color.accent,
    muted: Util.alpha(Commons.Color.foreground, 0.55),
    fontFamily: Style.font.family
  })

  readonly property var tabs: [
    { id: "general", title: "General", glyph: "\uf013" },
    { id: "search", title: "Search", glyph: "\uf002" },
    { id: "commands", title: "Commands", glyph: "\uf120" },
    { id: "snippets", title: "Snippets", glyph: "\uf121" },
    { id: "quicklinks", title: "Quicklinks", glyph: "\uf0c1" },
    { id: "paste", title: "Paste & Copy", glyph: "\uf0ea" },
    { id: "calculator", title: "Calculator", glyph: "\uf1ec" },
    { id: "data", title: "Data", glyph: "\uf1c0" }
  ]

  // ---- hotkey recording (HotkeyField)

  property var recordingField: null

  function startRecording(field) {
    win.recordingField = field
    win.backend.callSync("hotkeys.record", { active: true })
    recordTimer.restart()
  }

  function stopRecording() {
    if (!win.recordingField) return
    win.recordingField = null
    recordTimer.stop()
    win.backend.callSync("hotkeys.record", { active: false })
  }

  // Never leave Hyprland in the recording submap, where no bindings work.
  Timer { id: recordTimer; interval: 10000; onTriggered: { win.stopRecording(); win.flash("Stopped recording", false) } }
  onVisibleChanged: if (!win.visible) win.stopRecording()
  Component.onDestruction: win.stopRecording()

  // owner: "launcher" or a command id; hotkey "" removes it.
  function assignHotkey(owner, hotkey) {
    var conflicts = hotkey ? (win.backend.callSync("hotkeys.conflicts", { hotkey: hotkey }).data || []) : []
    var r = owner === "launcher"
      ? win.backend.callSync("settings.updateGeneralSettings", { launcherHotkey: hotkey })
      : win.backend.callSync("settings.updateCommandSettings", { commandId: owner, hotkey: hotkey })
    if (!r.ok) { win.flash(r.error, true); return }
    var shown = Hotkeys.display(hotkey)
    if (!win.backend.hotkeysLoaded) win.flash("Saved, but Hyprland doesn't load oma-cast's hotkeys yet: run oma-cast setup hyprland", true)
    else if (conflicts.length) win.flash(shown + " saved. It replaces Omarchy's “" + conflicts.join("”, “") + "”", false)
    else win.flash(hotkey ? shown + " saved" : "Hotkey removed", false)
  }

  function open(target) {
    var t = target || {}
    if (t.tab && win.tabs.some(function(x) { return x.id === t.tab })) win.tab = t.tab
    win.visible = true
    if (t.snippetId) Qt.callLater(function() { snippetsPage.select(t.snippetId) })
    if (t.quicklinkId) Qt.callLater(function() { quicklinksPage.select(t.quicklinkId) })
  }

  function close() { win.visible = false }

  function flash(text, isError) {
    win.message = String(text || "")
    win.messageIsError = !!isError
    messageTimer.restart()
  }

  Timer { id: messageTimer; interval: 4000; onTriggered: win.message = "" }

  // Imports from the clipboard and exports report back asynchronously.
  Connections {
    target: win.backend
    function onNotification(method, data) {
      if (!win.visible) return
      if (method === "snippets.imported" || method === "snippets.exported" || method === "quicklinks.imported" || method === "quicklinks.exported"
          || method === "backup.exported" || method === "data.restored")
        win.flash(data.title, !data.ok)
    }
  }

  Shortcut { sequence: "Ctrl+W"; enabled: !win.recordingField; onActivated: win.close() }
  Shortcut { sequence: "Escape"; enabled: !win.recordingField; onActivated: win.close() }
  Shortcut {
    sequence: "Ctrl+S"
    enabled: !win.recordingField
    onActivated: {
      if (win.tab === "snippets") snippetsPage.save()
      else if (win.tab === "quicklinks") quicklinksPage.save()
    }
  }
  Repeater {
    model: win.tabs
    Item {
      required property var modelData
      required property int index
      Shortcut { sequence: "Ctrl+" + (index + 1); enabled: !win.recordingField; onActivated: win.tab = modelData.id }
    }
  }

  Rectangle {
    id: sidebar
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(200)
    color: Util.alpha(win.look.foreground, 0.03)

    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 1
      color: Util.alpha(win.look.foreground, 0.08)
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(4)

      Row {
        spacing: Style.space(8)
        bottomPadding: Style.space(14)
        topPadding: Style.space(6)
        leftPadding: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: ""
          color: win.look.accent
          font.family: "omarchy"
          font.pixelSize: Style.space(16)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "oma-cast"
          color: win.look.foreground
          font.family: win.look.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
      }

      Repeater {
        model: win.tabs

        Rectangle {
          id: tabRow
          required property var modelData
          required property int index
          width: parent.width
          height: Style.space(36)
          radius: Style.cornerRadius
          color: win.tab === tabRow.modelData.id ? Util.alpha(win.look.accent, 0.18)
            : (tabMouse.containsMouse ? Util.alpha(win.look.foreground, 0.05) : "transparent")

          Text {
            id: tabGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: tabRow.modelData.glyph
            color: win.tab === tabRow.modelData.id ? win.look.accent : win.look.foreground
            font.family: win.look.fontFamily
            font.pixelSize: Style.space(14)
          }
          Text {
            anchors.left: tabGlyph.right
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: tabRow.modelData.title
            color: win.look.foreground
            font.family: win.look.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Ctrl " + (tabRow.index + 1)
            color: win.look.muted
            opacity: tabMouse.containsMouse ? 1 : 0
            font.family: win.look.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.tab = tabRow.modelData.id
          }
        }
      }
    }
  }

  Item {
    id: pages
    anchors.left: sidebar.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: statusBar.top
    anchors.margins: Style.space(24)
    anchors.bottomMargin: Style.space(8)

    GeneralPage { anchors.fill: parent; visible: win.tab === "general"; backend: win.backend; host: win; look: win.look }
    SearchPage { anchors.fill: parent; visible: win.tab === "search"; backend: win.backend; host: win; look: win.look }
    CommandsPage { anchors.fill: parent; visible: win.tab === "commands"; backend: win.backend; host: win; look: win.look }
    SnippetsPage { id: snippetsPage; anchors.fill: parent; visible: win.tab === "snippets"; backend: win.backend; host: win; look: win.look }
    QuicklinksPage { id: quicklinksPage; anchors.fill: parent; visible: win.tab === "quicklinks"; backend: win.backend; host: win; look: win.look }
    PastePage { anchors.fill: parent; visible: win.tab === "paste"; backend: win.backend; host: win; look: win.look }
    CalculatorPage { anchors.fill: parent; visible: win.tab === "calculator"; backend: win.backend; host: win; look: win.look }
    DataPage { anchors.fill: parent; visible: win.tab === "data"; backend: win.backend; host: win; look: win.look }
  }

  Item {
    id: statusBar
    anchors.left: sidebar.right
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.space(34)

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: Util.alpha(win.look.foreground, 0.08)
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(24)
      anchors.right: hint.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: win.message
      color: win.messageIsError ? Commons.Color.urgent : win.look.foreground
      elide: Text.ElideRight
      font.family: win.look.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      id: hint
      anchors.right: parent.right
      anchors.rightMargin: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "Esc closes"
      color: win.look.muted
      font.family: win.look.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
