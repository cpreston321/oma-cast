import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Create and edit quicklinks (db/quicklinks.json, SPEC §8.4) with the same
// RPCs the launcher's form uses.
SettingsPage {
  id: page

  required property var backend
  required property var host

  tabId: "quicklinks"
  title: "Quicklinks"
  description: "Links and searches you open by name. {argument} placeholders become pills in the launcher."

  property string selectedId: ""
  property string openWith: ""
  property bool confirmDelete: false
  property string pendingSelect: ""

  readonly property var links: {
    page.backend.storeRevision
    page.backend.candidatesRevision
    var r = page.backend.ready ? page.backend.callSync("quicklinks.list", null) : null
    var list = r && r.ok ? r.data.slice() : []
    return list.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0) })
  }
  readonly property var stored: page.links.filter(function(l) { return l.id === page.selectedId })[0] || null
  readonly property bool dirty: page.selectedId === "new"
    ? !!(nameField.text || linkField.text || page.openWith)
    : !!page.stored && (nameField.text !== page.stored.name || linkField.text !== page.stored.link || page.openWith !== (page.stored.openWith || ""))

  readonly property var appChoices: {
    page.backend.candidatesRevision
    var r = page.backend.ready ? page.backend.callSync("quicklinks.openWithChoices", { query: "", current: page.openWith }) : null
    return (r && r.ok ? r.data : []).map(function(c) { return { value: c.id, label: c.title } })
  }

  function select(id) {
    if (id === page.selectedId) return
    if (page.dirty && page.pendingSelect !== id) {
      page.pendingSelect = id
      page.host.flash("Unsaved changes — click again to discard them", true)
      return
    }
    page.pendingSelect = ""
    page.confirmDelete = false
    page.selectedId = id
    var item = page.links.filter(function(l) { return l.id === id })[0]
    nameField.text = item ? item.name : ""
    linkField.text = item ? item.link : ""
    page.openWith = item ? (item.openWith || "") : ""
    if (id === "new") nameField.forceActiveFocus()
  }

  function save() {
    if (!page.selectedId) return
    var data = { name: nameField.text, link: linkField.text, openWith: page.openWith }
    if (page.selectedId !== "new") data.id = page.selectedId
    var r = page.backend.callSync(page.selectedId === "new" ? "quicklinks.save" : "quicklinks.update", data)
    if (!r.ok) { page.host.flash(r.error, true); return }
    page.selectedId = r.data.id
    page.host.flash("Quicklink saved", false)
  }

  function remove() {
    if (!page.confirmDelete) { page.confirmDelete = true; deleteTimer.restart(); return }
    var r = page.backend.callSync("quicklinks.delete", { id: page.selectedId })
    if (!r.ok) { page.host.flash(r.error, true); return }
    page.selectedId = ""
    page.confirmDelete = false
    page.host.flash("Quicklink deleted", false)
  }

  Timer { id: deleteTimer; interval: 3000; onTriggered: page.confirmDelete = false }

  LibraryList {
    id: library
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(250)
    look: page.look
    emptyText: "No quicklinks yet"
    selectedId: page.selectedId
    items: page.links.map(function(l) { return { id: l.id, title: l.name, subtitle: l.link } })
    onPicked: function(id) { page.select(id) }
    onCreateRequested: page.select("new")
    onImportRequested: {
      var r = page.backend.callSync("quicklinks.import", {})
      page.host.flash(r.ok ? r.data.title : r.error, !r.ok)
    }
    onExportRequested: {
      var r = page.backend.callSync("quicklinks.export", null)
      if (!r.ok) page.host.flash(r.error, true)
      else if (r.data.toast) page.host.flash(r.data.toast.title, r.data.toast.style === "failure")
    }
  }

  Item {
    anchors.left: library.right
    anchors.leftMargin: Style.space(18)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    Text {
      anchors.centerIn: parent
      visible: !page.selectedId
      width: parent.width * 0.8
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "Pick a quicklink to edit it, or press New."
      color: page.look.muted
      wrapMode: Text.Wrap
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      visible: !!page.selectedId
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(6)

      FieldLabel { look: page.look; text: "Name" }
      TextField {
        id: nameField
        width: parent.width
        placeholderText: "Search GitHub"
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.body
      }
      Item { width: 1; height: Style.space(4) }
      FieldLabel { look: page.look; text: "Link" }
      TextField {
        id: linkField
        width: parent.width
        placeholderText: "https://github.com/search?q={argument name=\"query\"}"
        font.family: "monospace"
        font.pixelSize: Style.font.bodySmall
      }
      Item { width: 1; height: Style.space(4) }
      FieldLabel { look: page.look; text: "Open with" }
      SearchSelect {
        width: Math.min(parent.width, Style.space(320))
        showLabel: false
        placeholderText: "Search apps…"
        options: page.appChoices
        value: page.openWith
        onChanged: function(v) { page.openWith = v }
      }
      Item { width: 1; height: Style.space(4) }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Web links open in your browser; files and folders with xdg-open. Placeholders: {argument name=\"…\" default=\"…\"}, {clipboard}, {selection}, {date}, {uuid}."
        color: page.look.muted
        wrapMode: Text.Wrap
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      visible: !!page.selectedId
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      spacing: Style.space(8)

      Button {
        visible: page.selectedId !== "new"
        text: page.confirmDelete ? "Click again to delete" : "Delete"
        onClicked: page.remove()
      }
      Button {
        text: page.selectedId === "new" ? "Create Quicklink" : "Save"
        tooltipText: "Ctrl+S"
        bordered: true
        active: page.dirty
        enabled: page.dirty
        onClicked: page.save()
      }
    }
  }
}
