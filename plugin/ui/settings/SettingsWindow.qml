import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../core/Hotkeys.js" as Hotkeys

// The Settings window (fork, SPEC §10.5): a normal Hyprland window with a
// sidebar of pages. open({tab, snippetId?, quicklinkId?}) shows it on a page,
// optionally with an item open in its editor ("new" for a fresh one). A tab
// may also name an extension ("calculator", "ai"…), which opens it on the
// Extensions page. The sidebar's search finds any setting on any page.
FloatingWindow {
  id: win

  required property var backend

  property string tab: "general"
  property bool showAdvanced: false
  property string searchText: ""
  property int resultIndex: 0
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
    fontFamily: Style.font.family,
    advanced: win.showAdvanced
  })

  readonly property var tabs: [
    { id: "general", title: "General", glyph: "\uf013" },
    { id: "search", title: "Search", glyph: "\uf002" },
    { id: "extensions", title: "Extensions", glyph: "\uf12e" },
    { id: "commands", title: "All Commands", glyph: "\uf120" },
    { id: "snippets", title: "Snippets", glyph: "\uf121" },
    { id: "quicklinks", title: "Quicklinks", glyph: "\uf0c1" },
    { id: "data", title: "Data", glyph: "\uf1c0" }
  ]
  // Tabs that became extensions keep working in open() and the CLI.
  readonly property var movedTabs: ({ paste: "clipboard", calculator: "calculator", ai: "ai" })

  // ---- settings search: every SettingRow on every page, found by its
  // label, description, keywords and where it lives.

  function collectRows(item, out) {
    if (!item) return
    if (item.isSettingRow) { out.push(item); return }
    var kids = item.children
    for (var i = 0; i < kids.length; i++) win.collectRows(kids[i], out)
  }

  function locate(row) {
    var loc = { tab: "", tabTitle: "", extension: "", extensionTitle: "", card: "", advanced: !!row.advanced }
    for (var p = row.parent; p; p = p.parent) {
      if (p.isSettingsCard && !loc.card) { loc.card = p.title; loc.advanced = loc.advanced || p.advanced }
      if (p.extensionId && !loc.extension) { loc.extension = p.extensionId; loc.extensionTitle = p.title }
      if (p.tabId) { loc.tab = p.tabId; break }
    }
    var t = win.tabs.filter(function(x) { return x.id === loc.tab })[0]
    loc.tabTitle = t ? t.title : loc.tab
    return loc
  }

  readonly property var searchResults: {
    var words = win.searchText.trim().toLowerCase().split(/\s+/).filter(function(w) { return w })
    if (!words.length) return []
    function matches(hay) { hay = hay.toLowerCase(); return words.every(function(w) { return hay.indexOf(w) >= 0 }) }
    var out = []
    // Pages and extensions by name.
    win.tabs.forEach(function(t) { if (matches(t.title)) out.push({ title: t.title, path: "Page", tab: t.id, extension: "", row: null, score: 0 }) })
    extensionsPage.extensions.forEach(function(e) {
      if (matches(e.title + " extension")) out.push({ title: e.title, path: "Extensions", tab: "extensions", extension: e.id, row: null, score: 0 })
    })
    var rows = []
    win.collectRows(pages, rows)
    rows.forEach(function(row) {
      var loc = win.locate(row)
      var where = [loc.extensionTitle || loc.tabTitle, loc.card].filter(function(x) { return x }).join(" › ")
      if (!matches([row.label, row.description, row.keywords, where].join(" "))) return
      out.push({ title: row.label, path: where, tab: loc.tab, extension: loc.extension, advanced: loc.advanced, row: row,
        score: win.labelScore(row.label, words) })
    })
    // Stable: Qt's sort isn't.
    out = out.map(function(r, i) { r.order = i; return r })
    out.sort(function(a, b) { return a.score - b.score || a.order - b.order })
    return out.slice(0, 60)
  }
  onSearchResultsChanged: win.resultIndex = 0

  // 1: every word starts a word of the label; 2: the label contains them;
  // 3: they match elsewhere (description, keywords, place). Pages are 0.
  function labelScore(label, words) {
    var l = String(label).toLowerCase()
    var starts = l.split(/[^a-z0-9]+/)
    if (words.every(function(w) { return starts.some(function(s) { return s.indexOf(w) === 0 }) })) return 1
    if (words.every(function(w) { return l.indexOf(w) >= 0 })) return 2
    return 3
  }

  function jump(result) {
    if (!result) return
    if (result.advanced) win.showAdvanced = true
    win.tab = result.tab
    if (result.extension) extensionsPage.selected = result.extension
    if (result.row) Qt.callLater(function() { result.row.reveal() })
  }

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
    var ext = t.extension || win.movedTabs[t.tab] || (extensionsPage.has(t.tab) ? t.tab : "")
    if (ext && extensionsPage.has(ext)) { win.tab = "extensions"; extensionsPage.selected = ext }
    else if (t.tab && win.tabs.some(function(x) { return x.id === t.tab })) win.tab = t.tab
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
  // Esc clears the settings search first.
  Shortcut {
    sequence: "Escape"
    enabled: !win.recordingField
    onActivated: { if (searchField.text) searchField.text = ""; else win.close() }
  }
  Shortcut { sequence: "Ctrl+F"; enabled: !win.recordingField; onActivated: searchField.forceActiveFocus() }
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
    width: Style.space(190)
    color: Util.alpha(win.look.foreground, 0.03)

    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 1
      color: Util.alpha(win.look.foreground, 0.08)
    }

    // Rows marked advanced stay hidden until this is on.
    Item {
      id: advancedRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(12)
      height: Style.space(34)
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Show advanced"
        color: win.look.muted
        font.family: win.look.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      ToggleSwitch {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: win.showAdvanced
        onToggled: win.showAdvanced = !win.showAdvanced
      }
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

      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Search settings…"
        font.family: win.look.fontFamily
        font.pixelSize: Style.font.bodySmall
        onTextChanged: win.searchText = text
        Keys.onPressed: function(event) {
          if (!win.searchText) return
          if (event.key === Qt.Key_Down) { win.resultIndex = Math.min(win.resultIndex + 1, win.searchResults.length - 1); event.accepted = true }
          else if (event.key === Qt.Key_Up) { win.resultIndex = Math.max(win.resultIndex - 1, 0); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { win.jump(win.searchResults[win.resultIndex]); event.accepted = true }
        }
      }
      Item { width: 1; height: Style.space(6) }

      // While searching, the matches replace the tabs.
      Text {
        visible: !!win.searchText && win.searchResults.length === 0
        width: parent.width
        textFormat: Text.PlainText
        text: "No settings match"
        color: win.look.muted
        wrapMode: Text.Wrap
        leftPadding: Style.space(6)
        font.family: win.look.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      ListView {
        id: resultList
        visible: !!win.searchText
        width: parent.width
        height: visible ? sidebar.height - y - advancedRow.height - Style.space(24) : 0
        clip: true
        model: win.searchResults
        currentIndex: win.resultIndex
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
          id: hit
          required property var modelData
          required property int index
          width: resultList.width
          height: hitText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: hit.index === win.resultIndex ? Util.alpha(win.look.accent, 0.18)
            : (hitMouse.containsMouse ? Util.alpha(win.look.foreground, 0.05) : "transparent")
          Column {
            id: hitText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: hit.modelData.title
              color: win.look.foreground
              elide: Text.ElideRight
              font.family: win.look.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: hit.modelData.path
              color: win.look.muted
              elide: Text.ElideRight
              font.family: win.look.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          MouseArea {
            id: hitMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { win.resultIndex = hit.index; win.jump(hit.modelData) }
          }
        }
      }

      Repeater {
        model: win.searchText ? [] : win.tabs

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
    ExtensionsPage { id: extensionsPage; anchors.fill: parent; visible: win.tab === "extensions"; backend: win.backend; host: win; look: win.look }
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
