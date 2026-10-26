import QtQuick
import Quickshell.Io

// Runs argv vectors (never a shell string) and reports
// callback(ok, stdout, stderr) once the process has exited and both streams
// are drained. Used by script menus (fork).
Item {
  id: runner

  property int active: 0
  readonly property bool running: runner.active > 0

  function run(argv, callback) {
    var proc = procComponent.createObject(runner, { callback: callback })
    proc.command = argv
    runner.active++
    proc.running = true
  }

  Component {
    id: procComponent

    Process {
      id: proc

      property var callback: null
      property int code: -1
      property bool exited: false
      property bool outDone: false
      property bool errDone: false

      function finish(failed) {
        if (!proc.callback) return
        if (!failed && !(proc.exited && proc.outDone && proc.errDone)) return
        var cb = proc.callback
        proc.callback = null
        runner.active--
        try {
          if (failed) cb(false, "", "Could not start " + String(proc.command[0] || "the command"))
          else cb(proc.code === 0, out.text, err.text)
        } finally {
          proc.destroy()
        }
      }

      stdout: StdioCollector {
        id: out
        waitForEnd: true
        onStreamFinished: { proc.outDone = true; proc.finish(false) }
      }
      stderr: StdioCollector {
        id: err
        waitForEnd: true
        onStreamFinished: { proc.errDone = true; proc.finish(false) }
      }
      onExited: function(exitCode) {
        proc.code = exitCode
        proc.exited = true
        proc.finish(false)
      }
      // A command that never starts emits no exit; give up on it.
      onRunningChanged: if (!proc.running && !proc.exited) startGuard.restart()

      property Timer startGuard: Timer {
        interval: 1000
        onTriggered: if (!proc.exited) proc.finish(true)
      }
    }
  }
}
