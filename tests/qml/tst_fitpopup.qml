// Settings dropdowns near the window bottom must open inside it (ui/settings/FitPopup.js).
import QtQuick
import QtQuick.Controls
import QtTest
import "../../plugin/ui/settings/FitPopup.js" as FitPopup

// Shaped like Omarchy's Dropdown: the Popup sits inside a nested trigger item.
Item {
  width: 400; height: 300
  Item {
    id: dropdown
    y: 260; width: 120; height: 30
    Item {
      id: trigger
      width: parent.width; height: 30
      Popup { id: popup; y: trigger.height; width: 120; height: 150 }
    }
    Component.onCompleted: FitPopup.fit(dropdown, 8)
  }
  TestCase {
    name: "Fit"; when: windowShown
    function test_fit() {
      compare(popup.margins, 8)
      popup.open(); wait(50)
      var bottom = popup.contentItem.mapToItem(null, 0, 0).y - popup.topPadding + popup.height
      popup.close()
      verify(bottom <= 300, "bottom " + bottom)
    }
  }
}
