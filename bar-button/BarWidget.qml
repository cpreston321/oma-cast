import QtQuick
import qs.Ui

// The Omarchy logo in the bar, opening oma-cast (fork). Right click opens a
// terminal, as Omarchy's own menu button does.
//
// A separate plugin of plain files: Qt refuses a bar widget reached through a
// symlinked plugin folder ("File name case mismatch"), and oma-cast itself is
// installed as a symlink into this repo. Install with: oma-cast install-button
BarWidget {
  id: root
  moduleName: "typecraft.oma-cast-button"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle typecraft.oma-cast '{}'")
    }
  }
}
