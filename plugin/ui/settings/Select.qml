import QtQuick
import qs.Commons
import qs.Ui
import "FitPopup.js" as FitPopup

// Omarchy's Dropdown, with its list kept inside the Settings window.
Dropdown {
  id: select
  Component.onCompleted: FitPopup.fit(select, Style.space(8))
}
