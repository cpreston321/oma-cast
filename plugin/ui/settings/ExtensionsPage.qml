import QtQuick
import qs.Commons
import qs.Ui

// Each built-in feature in one place, as in Raycast's Extensions: pick one on
// the left; its commands (alias, hotkey, on/off) and settings show on the
// right. Snippets and Quicklinks keep their editors in their own tabs.
SettingsPage {
  id: page

  required property var backend
  required property var host

  tabId: "extensions"
  property string selected: "clipboard"

  readonly property var extensions: [
    { id: "clipboard", title: "Clipboard", glyph: "" },
    { id: "emoji", title: "Emoji", glyph: "" },
    { id: "calculator", title: "Calculator", glyph: "" },
    { id: "ai", title: "AI", glyph: "\u{f06a9}" },
    { id: "files", title: "Files", glyph: "" },
    { id: "snippets", title: "Snippets", glyph: "" },
    { id: "quicklinks", title: "Quicklinks", glyph: "" },
    { id: "layouts", title: "Window Layouts", glyph: "\u{f148c}" },
    { id: "web", title: "Web Search", glyph: "" },
    { id: "omarchy", title: "Omarchy", glyph: "" }
  ]

  function has(id) { return page.extensions.some(function(e) { return e.id === id }) }

  readonly property var general: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({})
  }
  readonly property var choices: [{ value: "paste", label: "Paste" }, { value: "copy", label: "Copy" }]

  function setGeneral(patch, done) {
    var r = page.backend.callSync("settings.updateGeneralSettings", patch)
    if (!r.ok) page.host.flash(r.error, true)
    else if (done) page.host.flash(done, false)
    return r.ok
  }

  function list(text) {
    return String(text || "").split(/[,\n]/).map(function(t) { return t.trim() }).filter(function(t) { return t })
  }

  // ---- the list of extensions
  Rectangle {
    id: sideList
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(168)
    radius: Style.cornerRadius * 1.5
    color: Util.alpha(page.look.foreground, 0.035)
    border.width: 1
    border.color: Util.alpha(page.look.foreground, 0.07)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(2)

      Repeater {
        model: page.extensions
        Rectangle {
          id: extRow
          required property var modelData
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: page.selected === extRow.modelData.id ? Util.alpha(page.look.accent, 0.18)
            : (extMouse.containsMouse ? Util.alpha(page.look.foreground, 0.05) : "transparent")

          Text {
            id: extGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: extRow.modelData.glyph
            color: page.selected === extRow.modelData.id ? page.look.accent : page.look.foreground
            font.family: extRow.modelData.id === "omarchy" ? "omarchy" : page.look.fontFamily
            font.pixelSize: Style.space(14)
          }
          Text {
            anchors.left: extGlyph.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: extRow.modelData.title
            color: page.look.foreground
            elide: Text.ElideRight
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: extMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.selected = extRow.modelData.id
          }
        }
      }
    }
  }

  // ---- the selected extension
  Item {
    id: panes
    anchors.left: sideList.right
    anchors.leftMargin: Style.space(20)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "clipboard"
      title: "Clipboard History"
      description: "Everything you copy, from Omarchy's clipboard history: paste it again, or ask your agent about it."
      commandIds: ["builtin:clipboard-history"]
      backend: page.backend; host: page.host; look: page.look

      SettingsCard {
        look: page.look
        title: "Behaviour"
        SettingRow {
          look: page.look
          label: "↵ on an entry"
          description: "Paste types it into the window you came from. The other choice is on Ctrl ↵."
          keywords: "paste copy enter primary action"
          ButtonGroup { options: page.choices; value: page.general.clipboardPrimary || "paste"; onChanged: function(v) { page.setGeneral({ clipboardPrimary: v }) } }
        }
        SettingRow {
          look: page.look
          label: "Entries shown"
          description: "Omarchy decides how many it keeps; this is how many the list shows."
          keywords: "clipboard rows count limit"
          NumberField {
            from: 10
            to: 500
            stepSize: 10
            value: page.general.clipboardRows || 100
            onModified: function(v) { page.setGeneral({ clipboardRows: v }) }
          }
        }
      }
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "emoji"
      title: "Emoji"
      description: "Search emoji and symbols by name, and paste them where you were typing."
      commandIds: ["builtin:emoji"]
      backend: page.backend; host: page.host; look: page.look

      SettingsCard {
        look: page.look
        title: "Behaviour"
        SettingRow {
          look: page.look
          label: "↵ on an emoji"
          description: "The other choice is on Ctrl ↵."
          keywords: "paste copy enter primary action"
          ButtonGroup { options: page.choices; value: page.general.emojiPrimary || "paste"; onChanged: function(v) { page.setGeneral({ emojiPrimary: v }) } }
        }
        SettingRow {
          look: page.look
          label: "Frequently Used"
          description: "How many of your most-used emoji lead the grid. 0 hides the row. Data clears the history."
          keywords: "recent emoji count"
          NumberField {
            from: 0
            to: 64
            value: page.general.emojiFrequentCount === undefined ? 16 : page.general.emojiFrequentCount
            onModified: function(v) { page.setGeneral({ emojiFrequentCount: v }) }
          }
        }
      }
    }

    CalculatorPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "calculator"
      backend: page.backend; host: page.host; look: page.look
      primary: page.general.calculatorPrimary || "copy"
      onPrimaryChosen: function(v) { page.setGeneral({ calculatorPrimary: v }) }
    }

    AiPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "ai"
      backend: page.backend; host: page.host; look: page.look
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "files"
      title: "Files"
      description: "Find files and folders by name, in root search or with Search Files."
      commandIds: ["builtin:search-files"]
      backend: page.backend; host: page.host; look: page.look

      SettingsCard {
        look: page.look
        title: "Where to look"
        SettingRow {
          look: page.look
          label: "Folders to search"
          description: "Comma-separated, starting with ~ or /. Empty searches your home folder."
          keywords: "directories paths home"
          TextField {
            width: Style.space(300)
            placeholderText: "~"
            text: (page.general.fileFolders || []).join(", ")
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.bodySmall
            onEditingFinished: page.setGeneral({ fileFolders: page.list(text) }, "Folders saved")
          }
        }
        SettingRow {
          look: page.look
          label: "Skip"
          description: "Names or globs file search never enters, comma-separated."
          keywords: "exclude ignore node_modules"
          TextField {
            width: Style.space(300)
            placeholderText: "node_modules, __pycache__"
            text: (page.general.fileExcludes || []).join(", ")
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.bodySmall
            onEditingFinished: page.setGeneral({ fileExcludes: page.list(text) }, "Exclusions saved")
          }
        }
        SettingRow {
          look: page.look
          label: "Hidden files"
          description: "Include dotfiles and hidden folders."
          keywords: "dotfiles hidden"
          ToggleSwitch {
            checked: !!page.general.fileHidden
            onToggled: page.setGeneral({ fileHidden: !page.general.fileHidden })
          }
        }
      }
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "snippets"
      title: "Snippets"
      description: "Saved text with placeholders, pasted from the launcher, and AI Commands sent to your agent."
      commandIds: ["builtin:search-snippets", "builtin:create-snippet"]
      backend: page.backend; host: page.host; look: page.look

      SettingsCard {
        look: page.look
        title: "Behaviour"
        SettingRow {
          look: page.look
          label: "↵ on a snippet"
          description: "Paste also puts the caret at {cursor}. The other choice is on Ctrl ↵. AI Commands always go to your agent."
          keywords: "paste copy enter primary action"
          ButtonGroup { options: page.choices; value: page.general.snippetPrimary || "paste"; onChanged: function(v) { page.setGeneral({ snippetPrimary: v }) } }
        }
        SettingRow {
          look: page.look
          label: "Your snippets"
          description: "Write, import and export them in the Snippets tab."
          Button { text: "Open Snippets"; bordered: true; onClicked: page.host.tab = "snippets" }
        }
      }
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "quicklinks"
      title: "Quicklinks"
      description: "Links and commands with arguments, opened from the launcher. Any of them can also be a fallback (Search)."
      commandIds: ["builtin:search-quicklinks", "builtin:create-quicklink", "builtin:import-quicklinks", "builtin:export-quicklinks"]
      backend: page.backend; host: page.host; look: page.look

      SettingsCard {
        look: page.look
        title: "Library"
        SettingRow {
          look: page.look
          label: "Your quicklinks"
          description: "Edit them in the Quicklinks tab."
          Button { text: "Open Quicklinks"; bordered: true; onClicked: page.host.tab = "quicklinks" }
        }
      }
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "layouts"
      title: "Window Layouts"
      description: "Save the windows on a workspace and bring the arrangement back later. Everything else happens in the launcher."
      commandIds: ["builtin:layouts"]
      backend: page.backend; host: page.host; look: page.look
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "web"
      title: "Web Search"
      description: "Search the web with the query in a pill. The same searches are fallbacks under your results; order them in Search."
      commandIds: ["builtin:google-search", "builtin:duckduckgo-search"]
      backend: page.backend; host: page.host; look: page.look
    }

    ExtensionPane {
      anchors.fill: parent
      visible: page.selected === extensionId
      extensionId: "omarchy"
      title: "Omarchy"
      description: "Omarchy's menu and keybindings. Every menu action is a command too: give them aliases and hotkeys in Commands."
      commandIds: ["builtin:keybindings", "builtin:omarchy-menu", "builtin:settings"]
      backend: page.backend; host: page.host; look: page.look
    }
  }
}
