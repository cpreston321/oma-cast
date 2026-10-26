const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const S = require("../plugin/core/ScriptMenu.js")

const DOC = JSON.stringify({
  items: [
    { id: "save", label: "Save current layout…", icon: "x", input: { prompt: "Layout name", maxLength: 64, command: ["/bin/layouts", "save", "{input}"] } },
    { id: "nothing", label: "Does nothing" },
    { id: "bad", label: "Bad argv", command: "rm -rf /" },
    {
      id: "layout:gaming", label: "Gaming", description: "2 windows", trailingText: "Sep 4", badge: "2",
      command: ["/bin/layouts", "apply", "gaming"], closeOnSuccess: true,
      document: { command: ["/bin/layouts", "document", "gaming"] },
      actions: [
        { id: "delete", label: "Delete layout", tone: "danger", confirm: "Delete it?", confirmLabel: "Delete", command: ["/bin/layouts", "delete", "gaming"] },
        { id: "launch", label: "Apply and launch", command: ["/bin/layouts", "apply", "gaming", "--launch"], closeOnSuccess: true },
        { id: "rename", label: "Rename…", input: { prompt: "New name", default: "Gaming", command: ["/bin/layouts", "rename", "gaming", "{input}"] } },
        { id: "broken", label: "No command" }
      ]
    },
    { id: "layout:gaming", label: "Duplicate id", command: ["/bin/true"] },
    { id: "more", label: "More", submenu: { command: ["/bin/layouts", "preview-menu"] } }
  ]
})

test("parse keeps runnable items, rejects shell strings, and drops duplicates", () => {
  const { items, error } = S.parse(DOC)
  assert.equal(error, "")
  assert.deepEqual(items.map((i) => i.id), ["save", "layout:gaming", "more"])
  assert.deepEqual(items[1].actions.map((a) => a.id), ["delete", "launch", "rename"])
  assert.equal(S.parse("{").error, "The script printed invalid JSON")
  assert.equal(S.parse("{}").error, "The script printed no items")
})

test("row ids round-trip even when the item id has colons", () => {
  const id = S.rowId("layouts", "layout:gaming")
  assert.equal(id, "script:layouts:layout:gaming")
  assert.deepEqual(S.splitRowId(id), { menuKey: "layouts", itemId: "layout:gaming" })
  assert.equal(S.splitRowId("app:firefox"), null)
  assert.equal(S.menuKey(["a", "b"]), S.menuKey(["a", "b"]))
  assert.notEqual(S.menuKey(["a", "b"]), S.menuKey(["a", "c"]))
})

test("actions: open first, danger last, the first three get ↵ shortcuts", () => {
  const item = S.parse(DOC).items[1]
  const actions = S.actionsFor(item)
  assert.deepEqual(actions.map((a) => a.id), ["open", "script-action:launch", "script-action:rename", "script-action:delete"])
  assert.deepEqual(actions.map((a) => a.shortcut), ["↵", "Ctrl ↵", "Ctrl Shift ↵", ""])
  assert.equal(S.actionsFor(S.parse(DOC).items[0])[0].title, "Save current layout")
})

test("plan: confirm before destructive commands, push inputs and submenus, pick the run mode", () => {
  const [save, gaming, more] = S.parse(DOC).items
  const del = S.targetFor(gaming, "script-action:delete")
  assert.deepEqual(S.plan("layouts", gaming, del, "script-action:delete", false).confirm,
    { title: "Delete layout", message: "Delete it?", primary: "Delete", destructive: true })
  assert.deepEqual(S.plan("layouts", gaming, del, "script-action:delete", true), { run: ["/bin/layouts", "delete", "gaming"], mode: "wait" })
  assert.deepEqual(S.plan("layouts", gaming, gaming, "open", false), { run: ["/bin/layouts", "apply", "gaming"], mode: "close-on-success" })
  const input = S.plan("layouts", save, save, "open", false).push
  assert.equal(input.kind, "script-input")
  assert.equal(input.rowId, "script:layouts:save")
  const rename = S.plan("layouts", gaming, S.targetFor(gaming, "script-action:rename"), "script-action:rename", false).push
  assert.equal(rename.value, "Gaming")
  const sub = S.plan("layouts", more, more, "open", false).push
  assert.equal(sub.kind, "script-menu")
  assert.equal(sub.menuKey, S.menuKey(["/bin/layouts", "preview-menu"]))
  assert.equal(S.targetFor(gaming, "script-action:missing"), null)
})

test("input fills {input} as one argument, never re-split", () => {
  const save = S.parse(DOC).items[0]
  assert.deepEqual(S.planInput(save, "My $(id) layout"), { run: ["/bin/layouts", "save", "My $(id) layout"], mode: "wait" })
  assert.equal(S.planInput(save, "  ").error, "Layout name is required")
  assert.equal(S.planInput(save, "x".repeat(65)).error, "Layout name is too long")
})

test("summary is the last line printed; documents unfence code blocks", () => {
  assert.equal(S.summary("Building…\nSaved “Gaming” with 2 window(s).\n"), "Saved “Gaming” with 2 window(s).")
  assert.equal(S.summary(""), "")
  const doc = S.parseDocument(JSON.stringify({
    title: "Gaming", subtitle: "2 windows", status: "Exact geometry",
    stats: [{ label: "Windows", value: 2 }],
    sections: [{ heading: "Arrangement", format: "markdown", text: "```\n+--+\n|  |\n+--+\n```" }, { heading: "Note", text: "plain" }],
    fields: [{ label: "firefox", value: "ws 1" }]
  }))
  assert.deepEqual(doc.blocks, [{ heading: "Arrangement", text: "+--+\n|  |\n+--+", mono: true }, { heading: "Note", text: "plain", mono: false }])
  assert.deepEqual(doc.metadata, [{ label: "Windows", value: "2" }, { label: "firefox", value: "ws 1" }])
  assert.equal(S.parseDocument("nope"), null)
})

const SCRIPT = path.join(__dirname, "../plugin/extensions/layouts/layouts")

test("the bundled layouts script prints a menu this module accepts", () => {
  const state = fs.mkdtempSync(path.join(os.tmpdir(), "oma-cast-layouts-"))
  const out = execFileSync("python3", ["-I", SCRIPT, "menu", "--dir", path.dirname(SCRIPT)], { env: { ...process.env, HOME: state }, encoding: "utf8" })
  const { items, error } = S.parse(out)
  assert.equal(error, "")
  assert.ok(items.some((i) => i.id === "save" && i.input))
  assert.deepEqual(S.sourceCommand(S.sourceById("layouts"), "/p/plugin/"), ["/p/plugin/extensions/layouts/layouts", "menu", "--dir", "/p/plugin/extensions/layouts"])
  fs.rmSync(state, { recursive: true })
})

const ACTIONS = path.join(__dirname, "../plugin/extensions/user-actions/actions")

test("omalaunch's extensions.d action entries become root-search items", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "oma-cast-actions-"))
  const root = path.join(home, ".config/omarchy/omalaunch/extensions.d")
  fs.mkdirSync(path.join(root, "cams"), { recursive: true })
  fs.writeFileSync(path.join(root, "hello.json"), JSON.stringify({ id: "user.hello", mode: "action", label: "Hello", prefixes: ["hi"], command: ["{extensionDir}/hello"] }))
  fs.writeFileSync(path.join(root, "query.json"), JSON.stringify({ id: "user.q", mode: "query", label: "Typed", command: ["x"] }))
  fs.writeFileSync(path.join(root, "missing.json"), JSON.stringify({ id: "user.m", mode: "action", label: "Needs tool", requires: ["no-such-tool-xyz"], command: ["x"] }))
  fs.writeFileSync(path.join(root, "cams/provider"), "#!/bin/sh\necho '[{\"id\":\"user.cam.1\",\"mode\":\"action\",\"label\":\"Front\",\"rootDescription\":\"Open Front\",\"command\":[\"play\",\"1\"]}]'\n", { mode: 0o755 })
  const out = execFileSync("python3", ["-I", ACTIONS], { env: { ...process.env, HOME: home }, encoding: "utf8" })
  const { items } = S.parse(out)
  assert.deepEqual(items.map((i) => i.id), ["user.hello", "user.cam.1"])
  assert.deepEqual(items[0].command, [root + "/hello"])
  assert.deepEqual(items[0].keywords, ["hi"])
  assert.equal(S.candidate("user-actions", items[1], "Extensions", "Extension", "searching").subtitle, "Extensions")
  assert.deepEqual(S.plan("user-actions", items[1], items[1], "open", false), { run: ["play", "1"], mode: "dispatch" })
  fs.rmSync(home, { recursive: true })
})

test("a layout section becomes drawable screens; a bad one falls back to its text", () => {
  const doc = S.parseDocument(JSON.stringify({
    sections: [
      { heading: "Arrangement", format: "layout", text: "```\nascii\n```",
        screens: [{ label: "Workspace 2 · DP-1", width: 2048, height: 1152, reservedTop: 0.02,
          tiles: [{ x: 0, y: 0.02, w: 0.6875, h: 2, name: "Omakade", icon: "omakade", size: "1408 × 1126" }, null] }] },
      { heading: "Broken", format: "layout", screens: "nope", text: "```\nfallback\n```" }
    ]
  }))
  const [drawn, broken] = doc.blocks
  assert.equal(drawn.screens.length, 1)
  assert.equal(drawn.screens[0].aspect, 2048 / 1152)
  assert.deepEqual(drawn.screens[0].tiles, [{ x: 0, y: 0.02, w: 0.6875, h: 1, name: "Omakade", icon: "omakade", size: "1408 × 1126" }], "values clamp to the canvas")
  assert.deepEqual(broken, { heading: "Broken", text: "fallback", mono: true })
})
