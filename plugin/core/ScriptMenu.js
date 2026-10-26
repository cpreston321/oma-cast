// Script menus (fork, a port of omalaunch's "menu" extension mode). A script
// prints a menu document, {items: [...]}, and oma-cast renders it as a pushed
// view. Each item or action runs an argv vector (never a shell string):
//
//   item:   {id, label, description?, icon?, badge?, trailingText?,
//            command? | submenu: {command} | input: {prompt, default?, maxLength?, command},
//            confirm?, confirmLabel?, tone?, closeOnDispatch?, closeOnSuccess?,
//            document?: {command}, actions?: [action]}
//   action: the same, minus submenu, document and actions.
//
// `{input}` in an input command is replaced by the typed text. A document
// command prints {title, subtitle, status, stats, sections, fields} for the
// detail pane.

var MAX_ITEMS = 500
var MAX_ACTIONS = 16
var MAX_ARGS = 64
var MAX_INPUT = 256

// Scripts bundled with the plugin, relative to plugin/. `globalSearch` puts
// the top-level items in root search while typing.
var SOURCES = [
  {
    id: "layouts",
    title: "Window Layouts",
    glyph: "󱒌",
    keywords: ["layout", "layouts", "windows", "arrange", "workspace", "restore", "save"],
    dir: "extensions/layouts",
    command: ["{dir}/layouts", "menu", "--dir", "{dir}"],
    typeLabel: "Layout",
    globalSearch: true
  },
  {
    // Action entries from omalaunch's ~/.config/omarchy/omalaunch/extensions.d,
    // found by root search only (no view of their own).
    id: "user-actions",
    title: "Extensions",
    dir: "extensions/user-actions",
    command: ["{dir}/actions"],
    typeLabel: "Extension",
    globalSearch: true
  }
]

function sourceById(id) {
  return SOURCES.filter(function(s) { return s.id === id })[0] || null
}

// The source's menu command with {dir} resolved against the plugin directory.
function sourceCommand(source, pluginDir) {
  var dir = String(pluginDir || "").replace(/\/+$/, "") + "/" + source.dir
  return source.command.map(function(arg) { return arg.split("{dir}").join(dir) })
}

function argv(value) {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_ARGS) return null
  for (var i = 0; i < value.length; i++) if (typeof value[i] !== "string") return null
  return value[0] ? value.slice() : null
}

function text(value, max) {
  return typeof value === "string" ? value.slice(0, max || 256) : ""
}

function normalizeEntry(raw, nested) {
  if (!raw || typeof raw !== "object") return null
  var id = text(raw.id, 128)
  var label = text(raw.label || raw.title)
  if (!id || !label) return null
  var entry = {
    id: id, label: label,
    description: text(raw.description),
    icon: text(raw.icon, 8),
    badge: text(raw.badge, 32),
    trailingText: text(raw.trailingText, 64),
    tone: raw.tone === "danger" ? "danger" : "",
    confirm: text(raw.confirm),
    confirmLabel: text(raw.confirmLabel, 32),
    closeOnDispatch: raw.closeOnDispatch === true,
    closeOnSuccess: raw.closeOnSuccess === true,
    command: argv(raw.command),
    keywords: Array.isArray(raw.keywords) ? raw.keywords.filter(function(k) { return typeof k === "string" }).slice(0, 16).map(function(k) { return k.slice(0, 64) }) : [],
    input: null, submenu: null, document: null, actions: []
  }
  if (raw.input && typeof raw.input === "object" && argv(raw.input.command)) {
    var max = Number(raw.input.maxLength)
    entry.input = {
      prompt: text(raw.input.prompt) || label,
      value: text(raw.input["default"], MAX_INPUT),
      maxLength: max > 0 ? Math.min(MAX_INPUT, Math.floor(max)) : MAX_INPUT,
      command: argv(raw.input.command)
    }
  }
  if (!nested) {
    if (raw.submenu && typeof raw.submenu === "object" && argv(raw.submenu.command)) entry.submenu = { command: argv(raw.submenu.command) }
    if (raw.document && typeof raw.document === "object" && argv(raw.document.command)) entry.document = { command: argv(raw.document.command) }
    var actions = Array.isArray(raw.actions) ? raw.actions : []
    for (var i = 0; i < actions.length && entry.actions.length < MAX_ACTIONS; i++) {
      var action = normalizeEntry(actions[i], true)
      if (action && (action.command || action.input)) entry.actions.push(action)
    }
  }
  return entry
}

// {items, error}. An item that can do nothing is dropped.
function parse(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return { items: [], error: "The script printed invalid JSON" } }
  var source = parsed && Array.isArray(parsed.items) ? parsed.items : (Array.isArray(parsed) ? parsed : null)
  if (!source) return { items: [], error: "The script printed no items" }
  var items = []
  var seen = {}
  for (var i = 0; i < source.length && items.length < MAX_ITEMS; i++) {
    var item = normalizeEntry(source[i], false)
    if (!item || seen["$" + item.id] || !(item.command || item.input || item.submenu || item.document)) continue
    seen["$" + item.id] = true
    items.push(item)
  }
  return { items: items, error: "" }
}

// Row ids are "script:<menuKey>:<itemId>". A source's own menu is keyed by
// the source id, so favourites and aliases on its items survive restarts.
function rowId(menuKey, itemId) {
  return "script:" + menuKey + ":" + itemId
}

function splitRowId(id) {
  var value = String(id || "")
  if (value.indexOf("script:") !== 0) return null
  var rest = value.slice(7)
  var at = rest.indexOf(":")
  return at > 0 ? { menuKey: rest.slice(0, at), itemId: rest.slice(at + 1) } : null
}

// A stable key for a submenu command (djb2 over its arguments).
function menuKey(command) {
  var s = JSON.stringify(command)
  var h = 5381
  for (var i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
  return "m" + h.toString(36)
}

function candidate(menuKey, item, location, typeLabel, when) {
  return {
    id: rowId(menuKey, item.id), type: "command", kind: "script",
    title: item.label,
    subtitle: location ? location : item.description,
    keywords: (location && item.description ? [item.description] : []).concat(item.keywords || []),
    glyph: item.icon, glyphFont: "",
    typeLabel: typeLabel || item.trailingText || item.badge || "",
    hasDocument: !!item.document,
    rootSearch: { when: when || "always" }
  }
}

// deps.decorate adds aliases, favourites and frecency (RootSearch.decorate).
function sections(key, items, query, ctx, deps) {
  var list = items.map(function(item) {
    return deps.decorate(candidate(key, item, "", "", "always"))
  })
  var q = String(query || "").trim()
  if (!q) return list.length ? [{ id: "menu", title: "", rows: list.map(function(c) { return { candidate: c, record: null } }) }] : []
  var ranked = deps.Ranker.rank(list, q, { sensitivity: ctx.sensitivity || "medium", nowMs: ctx.nowMs })
  return ranked.length ? [{ id: "results", title: "Results", rows: ranked }] : []
}

// Ctrl+K actions for an item: "open" first, then the item's own actions.
// ↵, Ctrl+↵ and Ctrl+Shift+↵ run the first three (LauncherWindow.performNth).
var NTH_SHORTCUTS = ["↵", "Ctrl ↵", "Ctrl Shift ↵"]

function primaryTitle(item) {
  if (item.submenu) return "Open"
  if (item.input) return item.label.replace(/…$/, "")
  if (!item.command && item.document) return "Show Details"
  return "Run"
}

function actionsFor(item) {
  // Danger actions go last. Partitioned by hand: Array.sort is not stable in
  // Qt's JS engine, and the order decides what ↵ runs.
  var list = [{ id: "open", title: primaryTitle(item), section: "primary", icon: "" }]
  var danger = []
  for (var i = 0; i < item.actions.length; i++) {
    var a = item.actions[i]
    var entry = { id: "script-action:" + a.id, title: a.label, section: a.tone === "danger" ? "delete" : "actions", icon: a.icon }
    if (a.tone === "danger") danger.push(entry)
    else list.push(entry)
  }
  list = list.concat(danger)
  for (var n = 0; n < list.length; n++) list[n].shortcut = NTH_SHORTCUTS[n] || ""
  return list
}

function targetFor(item, actionId) {
  if (actionId === "open") return item
  var id = String(actionId || "").replace(/^script-action:/, "")
  return item.actions.filter(function(a) { return a.id === id })[0] || null
}

function fillInput(command, value) {
  var v = String(value || "")
  return command.map(function(arg) { return arg.split("{input}").join(v) })
}

// What running `target` means, before anything is executed:
//   {push}         a submenu or an input prompt
//   {confirm}      ask first (unless confirmed)
//   {run, mode}    mode "dispatch" closes now; "close-on-success" waits and
//                  closes on exit 0; "wait" waits and stays open.
function plan(key, item, target, actionId, confirmed) {
  if (target.submenu) return { push: { kind: "script-menu", menuKey: menuKey(target.submenu.command), command: target.submenu.command, title: target.label } }
  if (target.input) {
    return { push: {
      kind: "script-input", title: target.input.prompt, value: target.input.value, maxLength: target.input.maxLength,
      rowId: rowId(key, item.id), actionId: actionId
    } }
  }
  if (!target.command) return target.document ? { detail: true } : { error: "Nothing to run" }
  if (target.confirm && !confirmed) {
    return { confirm: { title: target.label.replace(/…$/, ""), message: target.confirm, primary: target.confirmLabel || "Continue", destructive: target.tone === "danger" } }
  }
  return { run: target.command, mode: target.closeOnDispatch ? "dispatch" : (target.closeOnSuccess ? "close-on-success" : "wait") }
}

function planInput(target, value) {
  var v = String(value || "")
  if (!target || !target.input) return { error: "Nothing to submit" }
  if (!v.trim()) return { error: target.input.prompt + " is required" }
  if (v.length > target.input.maxLength) return { error: target.input.prompt + " is too long" }
  return {
    run: fillInput(target.input.command, v),
    mode: target.closeOnDispatch ? "dispatch" : (target.closeOnSuccess ? "close-on-success" : "wait")
  }
}

// The last non-empty line a command printed: its own summary of what it did.
function summary(output) {
  var lines = String(output || "").split(/\r?\n/).map(function(l) { return l.trim() }).filter(function(l) { return l })
  return lines.length ? lines[lines.length - 1].slice(0, 200) : ""
}

// A fenced block renders monospaced with its fences removed; other text is
// shown as written.
function block(heading, value) {
  var raw = String(value || "")
  var fenced = /^\s*```[^\n]*\n([\s\S]*?)\n?```\s*$/.exec(raw)
  return { heading: text(heading, 128), text: fenced ? fenced[1] : raw.trim(), mono: !!fenced }
}

function unit(value) {
  var n = Number(value)
  return isFinite(n) ? Math.max(0, Math.min(1, n)) : 0
}

// A "layout" section: monitor-shaped canvases with windows placed as
// fractions of them, drawn rather than shown as text.
//   screens: [{label, width, height, reservedTop, tiles: [{x, y, w, h, name, icon, size}]}]
function screens(value) {
  var out = []
  var list = Array.isArray(value) ? value : []
  for (var i = 0; i < list.length && out.length < 8; i++) {
    var s = list[i]
    if (!s || typeof s !== "object") continue
    var width = Number(s.width), height = Number(s.height)
    var tiles = (Array.isArray(s.tiles) ? s.tiles : []).slice(0, 32).filter(function(t) { return t && typeof t === "object" })
    out.push({
      label: text(s.label, 128),
      aspect: width > 0 && height > 0 ? width / height : 16 / 9,
      reservedTop: unit(s.reservedTop),
      tiles: tiles.map(function(t) {
        return { x: unit(t.x), y: unit(t.y), w: unit(t.w), h: unit(t.h), name: text(t.name, 64), icon: text(t.icon, 256), size: text(t.size, 32) }
      })
    })
  }
  return out
}

function section(raw) {
  var drawn = raw.format === "layout" ? screens(raw.screens) : []
  if (drawn.length) return { heading: text(raw.heading, 128), text: "", mono: false, screens: drawn }
  return block(raw.heading, raw.text)
}

// A document from a script, normalised for the detail pane:
// {title, subtitle, status, blocks: [{heading, text, mono, screens?}], metadata: [{label, value}]}.
function parseDocument(raw) {
  var doc
  try { doc = JSON.parse(String(raw || "")) } catch (e) { return null }
  if (!doc || typeof doc !== "object") return null
  var blocks = []
  var sections = Array.isArray(doc.sections) ? doc.sections : []
  for (var i = 0; i < sections.length && blocks.length < 16; i++) if (sections[i] && typeof sections[i] === "object") blocks.push(section(sections[i]))
  var metadata = []
  var pairs = [].concat(Array.isArray(doc.stats) ? doc.stats : [], Array.isArray(doc.fields) ? doc.fields : [])
  for (var j = 0; j < pairs.length && metadata.length < 32; j++) {
    var p = pairs[j]
    if (p && (p.label || p.value)) metadata.push({ label: text(p.label, 64), value: text(String(p.value === undefined ? "" : p.value), 256) })
  }
  return { title: text(doc.title), subtitle: text(doc.subtitle), status: text(doc.status, 64), blocks: blocks, metadata: metadata }
}

if (typeof module !== "undefined") {
  module.exports = {
    SOURCES: SOURCES,
    sourceById: sourceById,
    sourceCommand: sourceCommand,
    parse: parse,
    rowId: rowId,
    splitRowId: splitRowId,
    menuKey: menuKey,
    candidate: candidate,
    sections: sections,
    actionsFor: actionsFor,
    targetFor: targetFor,
    fillInput: fillInput,
    plan: plan,
    planInput: planInput,
    summary: summary,
    parseDocument: parseDocument
  }
}
