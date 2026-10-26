// Hotkeys (fork): the launcher's own and one per command, written by
// Settings into ~/.config/hypr/oma-cast.lua. A hotkey is Hyprland's notation,
// "SUPER + SHIFT + K": modifiers in a fixed order, then one key.

var MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MODIFIER_ALIASES = { SUPER: "SUPER", META: "SUPER", WIN: "SUPER", MOD4: "SUPER", CTRL: "CTRL", CONTROL: "CTRL", ALT: "ALT", MOD1: "ALT", SHIFT: "SHIFT" }

// Qt::KeyboardModifier flags (qnamespace.h).
var QT_SHIFT = 0x02000000, QT_CTRL = 0x04000000, QT_ALT = 0x08000000, QT_META = 0x10000000

// Qt::Key values to Hyprland key names. Letters and digits are handled by
// range. Shifted symbols map back to their US-layout key, since Hyprland
// binds the key, not the character.
var QT_KEYS = {
  0x20: "SPACE", 0x01000004: "RETURN", 0x01000005: "RETURN", 0x01000001: "TAB",
  0x01000003: "BACKSPACE", 0x01000007: "DELETE", 0x01000006: "INSERT", 0x01000000: "ESCAPE",
  0x01000010: "HOME", 0x01000011: "END", 0x01000016: "PAGE_UP", 0x01000017: "PAGE_DOWN",
  0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
  0x01000009: "PRINT",
  0x2c: "COMMA", 0x2e: "PERIOD", 0x2f: "SLASH", 0x3b: "SEMICOLON", 0x27: "APOSTROPHE",
  0x5b: "BRACKETLEFT", 0x5d: "BRACKETRIGHT", 0x5c: "BACKSLASH", 0x60: "GRAVE", 0x2d: "MINUS", 0x3d: "EQUAL",
  // Shift + digit / symbol on a US layout.
  0x21: "1", 0x40: "2", 0x23: "3", 0x24: "4", 0x25: "5", 0x5e: "6", 0x26: "7", 0x2a: "8", 0x28: "9", 0x29: "0",
  0x5f: "MINUS", 0x2b: "EQUAL", 0x7b: "BRACKETLEFT", 0x7d: "BRACKETRIGHT", 0x7c: "BACKSLASH",
  0x3a: "SEMICOLON", 0x22: "APOSTROPHE", 0x3c: "COMMA", 0x3e: "PERIOD", 0x3f: "SLASH", 0x7e: "GRAVE"
}
var NAMED_KEYS = ["SPACE", "RETURN", "TAB", "BACKSPACE", "DELETE", "INSERT", "ESCAPE", "HOME", "END",
  "PAGE_UP", "PAGE_DOWN", "LEFT", "UP", "RIGHT", "DOWN", "PRINT", "COMMA", "PERIOD", "SLASH", "SEMICOLON",
  "APOSTROPHE", "BRACKETLEFT", "BRACKETRIGHT", "BACKSLASH", "GRAVE", "MINUS", "EQUAL"]
// Qt reports a modifier key on its own while it is held; wait for the key.
var QT_MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000053, 0x01000054, 0x01001103, 0x01000024, 0x01000025]

function keyName(qtKey) {
  if (qtKey >= 0x41 && qtKey <= 0x5a) return String.fromCharCode(qtKey)        // A-Z
  if (qtKey >= 0x30 && qtKey <= 0x39) return String.fromCharCode(qtKey)        // 0-9
  if (qtKey >= 0x01000030 && qtKey <= 0x01000052) return "F" + (qtKey - 0x01000030 + 1)   // F1-F35
  return QT_KEYS[qtKey] || ""
}

function isFunctionKey(key) {
  return /^F([1-9]|[12][0-9]|3[0-5])$/.test(key)
}

function isKey(key) {
  return /^[A-Z0-9]$/.test(key) || isFunctionKey(key) || NAMED_KEYS.indexOf(key) >= 0
}

// {hotkey} for a recorded press, {pending} while only modifiers are held,
// or {error}. A hotkey needs a modifier unless it is a function key.
function fromQt(qtKey, qtModifiers) {
  if (QT_MODIFIER_KEYS.indexOf(qtKey) >= 0) return { pending: true }
  var key = keyName(qtKey)
  if (!key) return { error: "That key cannot be bound" }
  var mods = []
  if (qtModifiers & QT_META) mods.push("SUPER")
  if (qtModifiers & QT_CTRL) mods.push("CTRL")
  if (qtModifiers & QT_ALT) mods.push("ALT")
  if (qtModifiers & QT_SHIFT) mods.push("SHIFT")
  if (!mods.length && !isFunctionKey(key)) return { error: "Hold Super, Ctrl or Alt with the key" }
  if (mods.length === 1 && mods[0] === "SHIFT" && !isFunctionKey(key)) return { error: "Shift alone would block typing; add Super, Ctrl or Alt" }
  return { hotkey: mods.concat([key]).join(" + ") }
}

// Any spelling ("super+shift+k", "SUPER SHIFT + K", "Ctrl Alt Space") to
// {mods, key}, or null.
function parse(text) {
  var tokens = String(text || "").toUpperCase().replace(/\+/g, " ").split(/\s+/).filter(function(t) { return t })
  if (!tokens.length) return null
  var mods = []
  for (var i = 0; i < tokens.length - 1; i++) {
    var m = MODIFIER_ALIASES[tokens[i]]
    if (!m) return null
    if (mods.indexOf(m) < 0) mods.push(m)
  }
  var key = tokens[tokens.length - 1]
  if (key === "ENTER") key = "RETURN"
  if (!isKey(key)) return null
  mods.sort(function(a, b) { return MODIFIERS.indexOf(a) - MODIFIERS.indexOf(b) })
  return { mods: mods, key: key }
}

function normalize(text) {
  var p = parse(text)
  return p ? p.mods.concat([p.key]).join(" + ") : ""
}

// "" when fine, else why not.
function validate(text) {
  var p = parse(text)
  if (!p) return "Not a hotkey"
  if (!p.mods.length && !isFunctionKey(p.key)) return "A hotkey needs Super, Ctrl or Alt"
  if (p.mods.length === 1 && p.mods[0] === "SHIFT" && !isFunctionKey(p.key)) return "Shift alone would block typing"
  return ""
}

// "Super Shift K", for key caps.
function display(text) {
  var p = parse(text)
  if (!p) return ""
  var names = { SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", RETURN: "Return", SPACE: "Space", ESCAPE: "Esc",
    PAGE_UP: "PgUp", PAGE_DOWN: "PgDn", BACKSPACE: "Backspace", DELETE: "Del", PERIOD: ".", COMMA: ",", SLASH: "/",
    SEMICOLON: ";", APOSTROPHE: "'", BRACKETLEFT: "[", BRACKETRIGHT: "]", BACKSLASH: "\\", GRAVE: "`", MINUS: "-", EQUAL: "=",
    LEFT: "←", RIGHT: "→", UP: "↑", DOWN: "↓" }
  return p.mods.concat([p.key]).map(function(t) { return names[t] || t }).join(" ")
}

// Bindings already on a hotkey, from Omarchy's keybinding rows (Keybindings.js:
// {title, shortcut: "SUPER SHIFT + RETURN" or alternatives joined by " / "}).
// `ours` are hotkeys oma-cast itself binds, which never conflict.
function conflicts(hotkey, rows, ours) {
  var wanted = normalize(hotkey)
  if (!wanted) return []
  var own = (ours || []).map(normalize)
  if (own.indexOf(wanted) >= 0) return []
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var chords = String(rows[i].shortcut || "").split(" / ")
    for (var j = 0; j < chords.length; j++) if (normalize(chords[j]) === wanted && out.indexOf(rows[i].title) < 0) out.push(rows[i].title)
  }
  return out
}

function luaString(text) {
  return "\"" + String(text).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n").replace(/\r/g, "\\r")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "") + "\""
}

function shellQuote(text) {
  return "'" + String(text).replace(/'/g, "'\\''") + "'"
}

// The whole oma-cast.lua. launcher: a hotkey or ""; commands: [{hotkey,
// id, title}]. Each hotkey unbinds first, so it replaces an Omarchy default
// on the same keys (Settings shows that as a conflict before saving).
function luaFile(launcher, commands) {
  var lines = [
    "-- Written by oma-cast Settings. Changes here are overwritten: set hotkeys",
    "-- in oma-cast Settings (General and Commands) instead.",
    "",
    "-- An empty submap Settings enters while it records a hotkey, so Hyprland",
    "-- passes bound combos through to it. Super+Ctrl+Alt+Shift+F12 leaves it.",
    "hl.define_submap(\"oma-cast-record\", function()",
    "  hl.bind(\"SUPER + CTRL + ALT + SHIFT + F12\", hl.dsp.submap(\"reset\"), { description = \"Leave oma-cast hotkey recording\" })",
    "end)",
    ""
  ]
  var seen = {}
  function bind(hotkey, description, dispatcher) {
    var key = normalize(hotkey)
    if (!key || seen[key] || validate(key)) return
    seen[key] = true
    lines.push("hl.unbind(" + luaString(key) + ")")
    lines.push("o.bind(" + luaString(key) + ", " + luaString(description) + ", " + dispatcher + ")")
  }
  if (launcher) bind(launcher, "oma-cast", "hl.dsp.global(\"oma-cast:toggle\")")
  for (var i = 0; i < (commands || []).length; i++) {
    var c = commands[i]
    bind(c.hotkey, c.title, luaString("omarchy-shell oma-cast run " + shellQuote(c.id)))
  }
  return lines.join("\n") + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    fromQt: fromQt,
    parse: parse,
    normalize: normalize,
    validate: validate,
    display: display,
    conflicts: conflicts,
    luaString: luaString,
    shellQuote: shellQuote,
    luaFile: luaFile
  }
}
