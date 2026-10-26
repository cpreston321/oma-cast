import QtQuick
import qs.Commons
import qs.Ui
import "../../core/RootSearch.js" as RootSearch

// What root search shows: ranking looseness, Suggestions, keybinding and file
// rows, and the "Use <query> with…" fallbacks.
SettingsPage {
  id: page

  required property var backend
  required property var host

  title: "Search"
  description: "What turns up in root search as you type, and what's offered when nothing matches."

  readonly property var general: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({})
  }

  readonly property var quicklinks: {
    page.backend.storeRevision
    page.backend.candidatesRevision
    var r = page.backend.ready ? page.backend.callSync("quicklinks.list", null) : null
    return r && r.ok ? r.data : []
  }

  function setGeneral(patch) {
    var r = page.backend.callSync("settings.updateGeneralSettings", patch)
    if (!r.ok) page.host.flash(r.error, true)
    return r.ok
  }

  function list(text) {
    return String(text || "").split(/[,\n]/).map(function(t) { return t.trim() }).filter(function(t) { return t })
  }

  function fallbackTitle(id) {
    var builtin = RootSearch.FALLBACKS.filter(function(f) { return f.id === id })[0]
    if (builtin) return builtin.title
    var q = page.quicklinks.filter(function(l) { return "quicklink:" + l.id === id })[0]
    return q ? q.name + " (quicklink)" : id + " (missing)"
  }

  readonly property var fallbacks: page.general.fallbacks || []
  // What can still be added: unused built-ins, then quicklinks.
  readonly property var addable: RootSearch.FALLBACKS.map(function(f) { return { value: f.id, label: f.title } })
    .concat(page.quicklinks.map(function(l) { return { value: "quicklink:" + l.id, label: l.name + " (quicklink)" } }))
    .filter(function(o) { return page.fallbacks.indexOf(o.value) < 0 })

  function moveFallback(index, delta) {
    var next = page.fallbacks.slice()
    var to = index + delta
    if (to < 0 || to >= next.length) return
    var item = next.splice(index, 1)[0]
    next.splice(to, 0, item)
    page.setGeneral({ fallbacks: next })
  }

  SettingsForm {
    SettingRow {
      look: page.look
      label: "Search sensitivity"
      description: "How loosely a query may match: Low needs closer matches."
      ButtonGroup {
        options: [{ value: "low", label: "Low" }, { value: "medium", label: "Medium" }, { value: "high", label: "High" }]
        value: page.general.rootSearchSensitivity || "medium"
        onChanged: function(v) { page.setGeneral({ rootSearchSensitivity: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Suggestions"
      description: "How many of your most-used commands show when the search is empty. 0 hides them."
      NumberField {
        from: 0
        to: 20
        value: page.general.suggestionsLimit === undefined ? 6 : page.general.suggestionsLimit
        onModified: function(v) { page.setGeneral({ suggestionsLimit: v }) }
      }
    }
    SettingRow {
      look: page.look
      label: "Keybindings in root search"
      description: "Omarchy's shortcuts as results while you type. Search Keybindings lists them either way."
      ToggleSwitch {
        checked: page.general.rootKeybindings !== false
        onToggled: page.setGeneral({ rootKeybindings: page.general.rootKeybindings === false })
      }
    }
    SettingRow {
      look: page.look
      label: "Files in root search"
      description: "A Files section below the results. Search Files works either way."
      Row {
        spacing: Style.space(10)
        NumberField {
          visible: page.general.rootFiles !== false
          from: 1
          to: 20
          value: page.general.fileRootLimit || 5
          onModified: function(v) { page.setGeneral({ fileRootLimit: v }) }
        }
        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: page.general.rootFiles !== false
          onToggled: page.setGeneral({ rootFiles: page.general.rootFiles === false })
        }
      }
    }
    SettingRow {
      look: page.look
      label: "Folders to search"
      description: "Comma-separated, starting with ~ or /. Empty searches your home folder."
      TextField {
        width: Style.space(300)
        placeholderText: "~"
        text: (page.general.fileFolders || []).join(", ")
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.bodySmall
        onEditingFinished: { if (page.setGeneral({ fileFolders: page.list(text) })) page.host.flash("Folders saved", false) }
      }
    }
    SettingRow {
      look: page.look
      label: "Skip"
      description: "Names or globs file search never enters, comma-separated."
      TextField {
        width: Style.space(300)
        placeholderText: "node_modules, __pycache__"
        text: (page.general.fileExcludes || []).join(", ")
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.bodySmall
        onEditingFinished: { if (page.setGeneral({ fileExcludes: page.list(text) })) page.host.flash("Exclusions saved", false) }
      }
    }
    SettingRow {
      look: page.look
      label: "Hidden files"
      description: "Include dotfiles and hidden folders in file search."
      ToggleSwitch {
        checked: !!page.general.fileHidden
        onToggled: page.setGeneral({ fileHidden: !page.general.fileHidden })
      }
    }

    // ---- fallbacks
    Item { width: 1; height: Style.space(18) }
    FieldLabel { look: page.look; text: "“USE <QUERY> WITH…”" }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Offered below the results while you type, in this order. A quicklink gets the query as its first argument."
      color: page.look.muted
      wrapMode: Text.Wrap
      font.family: page.look.fontFamily
      font.pixelSize: Style.font.bodySmall
      bottomPadding: Style.space(6)
    }

    Repeater {
      model: page.fallbacks

      Item {
        id: fallbackRow
        required property string modelData
        required property int index
        width: parent ? parent.width : 0
        height: Style.space(40)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: (fallbackRow.index + 1) + ".  " + page.fallbackTitle(fallbackRow.modelData)
          color: page.look.foreground
          font.family: page.look.fontFamily
          font.pixelSize: Style.font.body
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)
          Button { text: "↑"; enabled: fallbackRow.index > 0; onClicked: page.moveFallback(fallbackRow.index, -1) }
          Button { text: "↓"; enabled: fallbackRow.index < page.fallbacks.length - 1; onClicked: page.moveFallback(fallbackRow.index, 1) }
          Button {
            text: "Remove"
            onClicked: page.setGeneral({ fallbacks: page.fallbacks.filter(function(f) { return f !== fallbackRow.modelData }) })
          }
        }
        Rectangle {
          visible: fallbackRow.index < page.fallbacks.length - 1
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Util.alpha(page.look.foreground, 0.06)
        }
      }
    }

    Item {
      width: parent ? parent.width : 0
      height: Style.space(48)
      visible: page.addable.length > 0

      SearchSelect {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(300)
        showLabel: false
        triggerLabel: "Add a fallback…"
        placeholderText: "Search fallbacks and quicklinks…"
        options: page.addable
        value: ""
        onChanged: function(v) { if (v) page.setGeneral({ fallbacks: page.fallbacks.concat([v]) }) }
      }
    }
  }
}
