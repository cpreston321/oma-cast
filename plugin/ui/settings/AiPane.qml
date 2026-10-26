import QtQuick
import qs.Commons
import qs.Ui

// The agent hand-off: which agent answers, how much of its plan is used,
// the "?" trigger and where sessions start. oma-cast itself runs no model;
// every question opens a terminal session with the agent (omarchy-agent).
ExtensionPane {
  id: page

  title: "AI"
  commandIds: ["builtin:ask-agent", "builtin:ask-selection"]
  description: "Questions from the launcher open a terminal session with your coding agent. oma-cast never talks to a model itself."

  onVisibleChanged: if (page.visible && page.backend.ready) page.backend.callSync("agent.refresh", null)

  readonly property var general: {
    page.backend.storeRevision
    var r = page.backend.ready ? page.backend.callSync("settings.getGeneralSettings", null) : null
    return r && r.ok ? r.data : ({})
  }

  readonly property var info: {
    page.backend.agentRevision
    var r = page.backend.ready ? page.backend.callSync("agent.list", null) : null
    return r && r.ok ? r.data : { agents: [], defaultAgent: "", known: [], checking: false, updatingUsage: false }
  }

  readonly property var agentOptions: page.info.agents.map(function(a) { return { value: a.id, label: a.name } })
  readonly property var withUsage: page.info.agents.filter(function(a) { return a.usage })

  function setGeneral(patch, done) {
    var r = page.backend.callSync("settings.updateGeneralSettings", patch)
    if (!r.ok) page.host.flash(r.error, true)
    else if (done) page.host.flash(done, false)
    return r.ok
  }

  SettingsCard {
    look: page.look
    title: "Agent"
      SettingRow {
        look: page.look
        keywords: "claude codex default model llm"
        label: "Default agent"
        description: page.info.agents.length ? "Answers the “Ask default agent” fallback, Ask Agent and AI Commands. Omarchy's other launchers use it too."
          : "No coding agent is installed. Install one from Omarchy Settings → AI."
        Select {
          visible: page.agentOptions.length > 0
          width: Style.space(220)
          showLabel: false
          options: page.agentOptions
          value: page.info.defaultAgent
          onChanged: function(v) {
            if (v === page.info.defaultAgent) return
            var r = page.backend.callSync("agent.setDefault", { id: v })
            page.host.flash(r.ok ? "Default agent saved" : r.error, !r.ok)
          }
        }
      }
      SettingRow {
        look: page.look
        keywords: "question mark trigger quick"
        label: "Ask prefix"
        description: "Type it, then a space and your question, to get one Ask row per installed agent. Empty turns it off."
        TextField {
          width: Style.space(80)
          placeholderText: "off"
          text: page.general.agentPrefix === undefined ? "?" : page.general.agentPrefix
          font.family: page.look.fontFamily
          font.pixelSize: Style.font.bodySmall
          onEditingFinished: { if (text !== page.general.agentPrefix) page.setGeneral({ agentPrefix: text.trim() }, "Ask prefix saved") }
        }
      }
      SettingRow {
        look: page.look
        keywords: "folder directory cwd work"
        label: "Start sessions in"
        description: "The folder new sessions open in, starting with ~ or /. Empty uses Omarchy's (~/Work). Asking about a file starts in its folder."
        TextField {
          width: Style.space(260)
          placeholderText: "~/Work"
          text: page.general.agentDirectory || ""
          font.family: page.look.fontFamily
          font.pixelSize: Style.font.bodySmall
          onEditingFinished: { if (text.trim() !== (page.general.agentDirectory || "")) page.setGeneral({ agentDirectory: text.trim() }, "Folder saved") }
        }
      }
  }
  SettingsCard {
    look: page.look
    title: "Usage"
    trailing: Button {
      text: page.info.updatingUsage ? "Updating…" : "Update"
      enabled: !page.info.updatingUsage
      bordered: true
      onClicked: page.backend.callSync("agent.updateUsage", null)
    }
      Text {
        width: parent.width
        topPadding: Style.space(10)
        bottomPadding: Style.space(10)
        visible: page.withUsage.length === 0
        textFormat: Text.PlainText
        text: "No usage recorded yet. Omarchy records it for agents that report plan limits; Update asks them now."
        color: page.look.muted
        wrapMode: Text.Wrap
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Repeater {
        model: page.withUsage
        Item {
          id: usageRow
          required property var modelData
          required property int index
          width: parent ? parent.width : 0
          height: Style.space(36)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: usageRow.modelData.name + (usageRow.modelData.isDefault ? "  (default)" : "")
            color: page.look.foreground
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: usageRow.modelData.usage
            color: page.look.muted
            font.family: page.look.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Rectangle {
            visible: usageRow.index < page.withUsage.length - 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Util.alpha(page.look.foreground, 0.06)
          }
        }
      }
  }
  SettingsCard {
    look: page.look
    title: "In the launcher"
      Text {
        width: parent.width
        topPadding: Style.space(10)
        bottomPadding: Style.space(10)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        lineHeight: 1.3
        color: page.look.muted
        font.family: page.look.fontFamily
        font.pixelSize: Style.font.bodySmall
        text: "• Ask Agent: a question pill; give it a hotkey or alias above.\n"
          + "• Ask About Selection: what you had selected in the app you came from.\n"
          + "• Ctrl+K → Ask Agent About This, on clipboard entries and files.\n"
          + "• “Ask default agent” under “Use <query> with…”; Ctrl+K there asks another agent. Order it in Search.\n"
          + "• AI Commands: in Snippets, turn on “Send to your agent” for a saved prompt."
      }
  }
}
