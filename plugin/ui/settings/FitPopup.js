.pragma library

// Omarchy's Dropdown and SearchableDropdown always open their list below the
// field, and a Qt Quick popup may then run past the window's bottom edge (it
// is clipped there on Wayland). A popup with margins >= 0 is kept inside the
// window instead, so this finds the popup inside `item` and sets them.
function fit(item, margin) {
  var stack = [item]
  for (var seen = 0; stack.length && seen < 400; seen++) {
    var o = stack.pop()
    if (o !== item && o.margins !== undefined && o.opened !== undefined) { o.margins = margin; continue }
    var kids = o.data || []
    for (var i = 0; i < kids.length; i++) if (kids[i]) stack.push(kids[i])
  }
}
