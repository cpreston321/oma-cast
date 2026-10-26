const test = require("node:test")
const assert = require("node:assert/strict")
const H = require("../plugin/core/Hotkeys.js")

const META = 0x10000000, CTRL = 0x04000000, ALT = 0x08000000, SHIFT = 0x02000000
const KEY = { A: 0x41, K: 0x4b, Space: 0x20, F5: 0x01000034, Exclam: 0x21, Period: 0x2e, Return: 0x01000004, Shift: 0x01000020, Meta: 0x01000022, Tilde: 0x7e }

test("a recorded press becomes Hyprland notation in a fixed modifier order", () => {
  assert.deepEqual(H.fromQt(KEY.K, SHIFT | META), { hotkey: "SUPER + SHIFT + K" })
  assert.deepEqual(H.fromQt(KEY.Space, ALT | CTRL), { hotkey: "CTRL + ALT + SPACE" })
  assert.deepEqual(H.fromQt(KEY.Return, META), { hotkey: "SUPER + RETURN" })
  assert.deepEqual(H.fromQt(KEY.Period, META), { hotkey: "SUPER + PERIOD" })
  assert.deepEqual(H.fromQt(KEY.F5, 0), { hotkey: "F5" }, "function keys may stand alone")
})

test("shifted symbols map back to their key, and modifiers alone wait", () => {
  assert.deepEqual(H.fromQt(KEY.Exclam, META | SHIFT), { hotkey: "SUPER + SHIFT + 1" })
  assert.deepEqual(H.fromQt(KEY.Tilde, CTRL | SHIFT), { hotkey: "CTRL + SHIFT + GRAVE" })
  assert.deepEqual(H.fromQt(KEY.Shift, SHIFT), { pending: true })
  assert.deepEqual(H.fromQt(KEY.Meta, META), { pending: true })
})

test("plain keys and Shift alone are refused: they would block typing", () => {
  assert.match(H.fromQt(KEY.A, 0).error, /Hold Super/)
  assert.match(H.fromQt(KEY.A, SHIFT).error, /Shift alone/)
  assert.equal(H.validate("a"), "A hotkey needs Super, Ctrl or Alt")
  assert.equal(H.validate("SHIFT + A"), "Shift alone would block typing")
  assert.equal(H.validate("SUPER + NOPE"), "Not a hotkey")
  assert.equal(H.validate("super+shift+k"), "")
})

test("any spelling normalizes; Omarchy's printed form compares equal", () => {
  assert.equal(H.normalize("shift super k"), "SUPER + SHIFT + K")
  assert.equal(H.normalize("SUPER SHIFT + RETURN"), "SUPER + SHIFT + RETURN")
  assert.equal(H.normalize("Ctrl Alt Space"), "CTRL + ALT + SPACE")
  assert.equal(H.normalize("control+enter"), "CTRL + RETURN")
  assert.equal(H.display("SUPER + ALT + PERIOD"), "Super Alt .")
})

test("conflicts list Omarchy bindings on the same keys, but not oma-cast's own", () => {
  const rows = [
    { title: "Omarchy menu", shortcut: "SUPER + SPACE" },
    { title: "Browser", shortcut: "SUPER SHIFT + RETURN" },
    { title: "Volume", shortcut: "XF86AudioRaiseVolume / SUPER + F5" }
  ]
  assert.deepEqual(H.conflicts("super+space", rows, []), ["Omarchy menu"])
  assert.deepEqual(H.conflicts("SUPER + SHIFT + RETURN", rows, []), ["Browser"])
  assert.deepEqual(H.conflicts("SUPER + F5", rows, []), ["Volume"], "alternatives are checked")
  assert.deepEqual(H.conflicts("SUPER + SPACE", rows, ["SUPER + SPACE"]), [])
  assert.deepEqual(H.conflicts("SUPER + J", rows, []), [])
})

test("the Lua file unbinds then binds each hotkey, quoting ids for the shell", () => {
  const lua = H.luaFile("SUPER + SPACE", [
    { hotkey: "ctrl alt space", id: "builtin:emoji", title: "Search Emoji" },
    { hotkey: "SUPER + ALT + L", id: "script:layouts:it's", title: 'Say "hi"' },
    { hotkey: "super + space", id: "dup", title: "Duplicate of the launcher" },
    { hotkey: "a", id: "bad", title: "Invalid" }
  ])
  assert.match(lua, /hl\.define_submap\("oma-cast-record"/)
  assert.match(lua, /hl\.unbind\("SUPER \+ SPACE"\)\no\.bind\("SUPER \+ SPACE", "oma-cast", hl\.dsp\.global\("oma-cast:toggle"\)\)/)
  assert.match(lua, /o\.bind\("CTRL \+ ALT \+ SPACE", "Search Emoji", "omarchy-shell oma-cast run 'builtin:emoji'"\)/)
  assert.ok(lua.includes(`o.bind("SUPER + ALT + L", "Say \\"hi\\"", "omarchy-shell oma-cast run 'script:layouts:it'\\\\''s'")`), lua)
  assert.equal(lua.split('o.bind("SUPER + SPACE"').length - 1, 1, "a duplicate hotkey is bound once")
  assert.ok(!lua.includes("Invalid"))
})
