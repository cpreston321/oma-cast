// Rows for CommandRow: every root-search command with its alias, hotkey and
// on/off state. opts: {ids: [command ids] to keep (in that order), show:
// "all"|"aliased"|"hotkeys"|"disabled", query}.
function build(candidates, settings, opts) {
  var o = opts || {}
  var q = String(o.query || "").trim().toLowerCase()
  var out = []
  for (var i = 0; i < candidates.length; i++) {
    var c = candidates[i]
    // Keybinding rows describe Omarchy's own shortcuts; files come and go.
    if (c.kind === "keybinding" || c.kind === "file" || c.kind === "folder") continue
    if (o.ids && o.ids.indexOf(c.id) < 0) continue
    var s = settings[c.id] || {}
    var disabled = s.enabled === false
    if (o.show === "disabled" && !disabled) continue
    if (o.show === "aliased" && !s.alias) continue
    if (o.show === "hotkeys" && !s.hotkey) continue
    if (q && (c.title + " " + c.subtitle + " " + (s.alias || "")).toLowerCase().indexOf(q) < 0) continue
    out.push({ id: c.id, title: c.title, subtitle: c.subtitle || c.typeLabel || "", glyph: c.glyph || "", glyphFont: c.glyphFont || "",
      iconName: c.iconName || "", alias: s.alias || "", hotkey: s.hotkey || "", disabled: disabled })
  }
  if (o.ids) out.sort(function(a, b) { return o.ids.indexOf(a.id) - o.ids.indexOf(b.id) })
  else out.sort(function(a, b) { return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : (a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0) })
  return out
}

if (typeof module !== "undefined") module.exports = { build: build }
