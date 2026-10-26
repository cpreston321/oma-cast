import QtQuick
import qs.Commons
import qs.Ui
import "FitPopup.js" as FitPopup

// Omarchy's SearchableDropdown, with its list kept inside the Settings window.
SearchableDropdown {
  id: select
  Component.onCompleted: FitPopup.fit(select, Style.space(8))
}
