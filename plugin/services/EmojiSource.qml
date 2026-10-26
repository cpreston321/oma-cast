import QtQuick
import Quickshell
import Quickshell.Io
import "../core/Emoji.js" as Emoji

// The emoji dataset Omarchy ships with its own picker, plus currency signs
// (fork, ported from omalaunch).
Item {
  id: source

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string path: source.omarchyPath + "/shell/plugins/emojis/emojis.json"
  property var values: Emoji.parse("")

  signal message(string level, string text, var metadata)

  FileView {
    path: source.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: source.values = Emoji.parse(text())
    onLoadFailed: {
      source.message("warning", "emoji dataset not found at " + source.path + "; only currency signs are available", null)
      source.values = Emoji.parse("")
    }
  }
}
