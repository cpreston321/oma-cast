import QtQuick
import Quickshell
import Quickshell.Io
import "../core/Clipboard.js" as Clipboard

// Omarchy's clipboard history, read-only (fork). The path matches the one
// Omarchy's paste helpers read, so a history index means the same entry to both.
Item {
  id: source

  readonly property string path: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property var entries: []
  property int revision: 0

  function entry(index) {
    for (var i = 0; i < source.entries.length; i++) if (source.entries[i].index === index) return source.entries[i]
    return null
  }

  FileView {
    path: source.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { source.entries = Clipboard.parse(text()); source.revision++ }
    onLoadFailed: { source.entries = []; source.revision++ }
  }
}
