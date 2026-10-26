import QtQuick
import Quickshell.Io

// Pastes or copies text (fork, for snippets). The text goes to wl-copy on
// stdin, never in argv, so a process listing cannot show it. Pasting waits
// for the launcher to unmap, presses Shift+Insert like Omarchy's own paste
// helper, then moves the caret back for a snippet's {cursor}.
Item {
  id: paster

  // text, "paste" or "copy", Left presses after pasting.
  function run(text, mode, cursorFromEnd) {
    var proc = procComponent.createObject(paster)
    proc.command = ["bash", "-c", paster.script, "bash", mode, String(Math.max(0, Math.min(2000, cursorFromEnd || 0)))]
    proc.pending = String(text)
    proc.running = true
  }

  readonly property string script: [
    'text=$(cat; printf x); text=${text%x}',
    'printf "%s" "$text" | wl-copy',
    '[[ $1 == copy ]] && exit 0',
    'sleep 0.15',
    'wtype -M shift -k Insert -m shift 2>/dev/null || true',
    'if (( $2 > 0 )); then',
    '  sleep 0.05',
    '  keys=(); for ((i = 0; i < $2; i++)); do keys+=(-k Left); done',
    '  wtype "${keys[@]}" 2>/dev/null || true',
    'fi'
  ].join("\n")

  Component {
    id: procComponent

    Process {
      id: proc
      property string pending: ""
      stdinEnabled: true
      onStarted: {
        proc.write(proc.pending)
        proc.pending = ""
        proc.stdinEnabled = false
      }
      onExited: proc.destroy()
    }
  }
}
