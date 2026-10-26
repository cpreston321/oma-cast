import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Create and edit snippets (db/snippets.json). Paste them from the
// launcher: Search Snippets, or type a snippet's name or keyword.
SettingsPage {
  id: page

  required property var backend
  required property var host

  title: "Snippets"
  description: "Saved text to paste from the launcher. Placeholders fill in when you paste."

  // "" nothing open, "new" a draft, else the id being edited.
  property string selectedId: ""
  property string error: ""
  property bool confirmDelete: false
  property string pendingSelect: ""

  readonly property var snippets: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("snippets.list", null) : null
    return r && r.ok ? r.data : []
  }
  readonly property var stored: page.snippets.filter(function(s) { return s.id === page.selectedId })[0] || null
  readonly property bool dirty: page.selectedId === "new"
    ? !!(nameField.text || keywordField.text || textArea.text)
    : !!page.stored && (nameField.text !== page.stored.name || keywordField.text !== (page.stored.keyword || "") || textArea.text !== page.stored.text)

  readonly property var placeholders: [
    { label: "Cursor", text: "{cursor}" },
    { label: "Clipboard", text: "{clipboard}" },
    { label: "Date", text: "{date}" },
    { label: "Time", text: "{time}" },
    { label: "Argument", text: "{argument name=\"name\"}" },
    { label: "UUID", text: "{uuid}" }
  ]

  // Switching away from unsaved changes asks for a second click.
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
    var item = page.snippets.filter(function(s) { return s.id === id })[0]
    nameField.text = item ? item.name : ""
    keywordField.text = item ? (item.keyword || "") : ""
    textArea.text = item ? item.text : ""
    page.error = ""
    if (id === "new") nameField.forceActiveFocus()
  }

  function draft() {
    return { id: page.selectedId === "new" ? "" : page.selectedId, name: nameField.text, keyword: keywordField.text, text: textArea.text }
  }

  function save() {
    if (!page.selectedId) return
    var r = page.backend.callSync(page.selectedId === "new" ? "snippets.save" : "snippets.update", page.draft())
    if (!r.ok) { page.error = r.error; page.host.flash(r.error, true); return }
    page.selectedId = r.data.id
    page.error = ""
    page.host.flash("Snippet saved", false)
  }

  function remove() {
    if (!page.confirmDelete) { page.confirmDelete = true; deleteTimer.restart(); return }
    var r = page.backend.callSync("snippets.delete", { id: page.selectedId })
    if (!r.ok) { page.host.flash(r.error, true); return }
    page.selectedId = ""
    page.confirmDelete = false
    page.host.flash("Snippet deleted", false)
  }

  function insert(token) {
    textArea.insert(textArea.cursorPosition, token)
    textArea.forceActiveFocus()
  }

  Timer { id: deleteTimer; interval: 3000; onTriggered: page.confirmDelete = false }

  // Checks the draft as it is typed, without saving.
  Timer {
    id: checkTimer
    interval: 250
    onTriggered: {
      if (!page.selectedId || !page.dirty) { page.error = ""; return }
      var r = page.backend.callSync("snippets.check", page.draft())
      page.error = r.ok ? r.data : r.error
    }
  }

  LibraryList {
    id: library
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(250)
    look: page.look
    emptyText: "No snippets yet"
    selectedId: page.selectedId
    items: page.snippets.map(function(s) { return { id: s.id, title: s.name, subtitle: s.keyword || s.text.replace(/\s+/g, " ").slice(0, 60) } })
    onPicked: function(id) { page.select(id) }
    onCreateRequested: page.select("new")
    onImportRequested: {
      var r = page.backend.callSync("snippets.import", {})
      page.host.flash(r.ok ? r.data.title : r.error, !r.ok)
    }
    onExportRequested: {
      var r = page.backend.callSync("snippets.export", null)
      if (!r.ok) page.host.flash(r.error, true)
      else if (r.data.toast) page.host.flash(r.data.toast.title, r.data.toast.style === "failure")
    }
  }

  Item {
    id: editor
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
      text: "Pick a snippet to edit it, or press New."
      color: page.look.muted
      wrapMode: Text.Wrap
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.body
    }

    Column {
      id: fields
      visible: !!page.selectedId
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(6)

      FieldLabel { look: page.look; text: "Name" }
      TextField {
        id: nameField
        width: parent.width
        placeholderText: "Email signature"
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.body
        onTextChanged: checkTimer.restart()
      }
      Item { width: 1; height: Style.space(4) }
      FieldLabel { look: page.look; text: "Keyword (optional)" }
      TextField {
        id: keywordField
        width: parent.width
        placeholderText: ";sig  — type it in the launcher to find this snippet"
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.body
        onTextChanged: checkTimer.restart()
      }
      Item { width: 1; height: Style.space(4) }
      Row {
        width: parent.width
        spacing: Style.space(6)
        FieldLabel { look: page.look; text: "Text"; anchors.verticalCenter: parent.verticalCenter }
        Item { width: Style.space(8); height: 1 }
        Repeater {
          model: page.placeholders
          Button {
            required property var modelData
            text: modelData.label
            tooltipText: "Insert " + modelData.text
            fontSize: Style.font.caption
            verticalPadding: Style.space(3)
            horizontalPadding: Style.space(8)
            onClicked: page.insert(modelData.text)
          }
        }
      }
    }

    ScrollView {
      id: textScroll
      visible: !!page.selectedId
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: fields.bottom
      anchors.topMargin: Style.space(6)
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(10)

      TextArea {
        id: textArea
        wrapMode: TextArea.Wrap
        selectByMouse: true
        placeholderText: "Best,\n{cursor}\n\nSent {date format=\"EEEE d MMMM\"}"
        color: page.look.foreground
        placeholderTextColor: page.look.muted
        selectionColor: Util.alpha(page.look.accent, 0.35)
        font.family: "monospace"
        font.pixelSize: Style.font.body
        onTextChanged: checkTimer.restart()
        background: Rectangle {
          radius: Math.max(Style.cornerRadius, Style.space(5))
          color: Util.alpha(page.look.foreground, 0.04)
          border.width: 1
          border.color: textArea.activeFocus ? page.look.accent : Util.alpha(page.look.foreground, 0.15)
        }
      }
    }

    Item {
      id: footer
      visible: !!page.selectedId
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(36)

      Text {
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: page.error || "{argument} becomes a pill in the launcher · {clipboard offset=1} is the entry before · {snippet name=\"…\"} nests one"
        color: page.error ? Commons.Color.urgent : page.look.muted
        elide: Text.ElideRight
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Button {
          visible: page.selectedId !== "new"
          text: page.confirmDelete ? "Click again to delete" : "Delete"
          onClicked: page.remove()
        }
        Button {
          text: page.selectedId === "new" ? "Create Snippet" : "Save"
          tooltipText: "Ctrl+S"
          bordered: true
          active: page.dirty
          enabled: page.dirty && !page.error
          onClicked: page.save()
        }
      }
    }
  }
}
