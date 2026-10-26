// Snippets (fork, SPEC §8.3, launcher only: no keyword expansion while
// typing in other apps). Saved text with placeholders, pasted from the
// launcher. Stored in db/snippets.json as
// items [{id, name, text, keyword, createdAt, updatedAt}].
//
// The placeholder lexer (quotes, escapes, modifiers, options) and date
// formatting come from Quicklinks.js through `deps.lexer`, so the grammar
// stays one implementation. Snippet rules differ: {cursor}, nested {snippet}
// and {calculator} are allowed, {selection} is not (Raycast keeps it off for
// snippets), and an unknown {word} is literal text, not an argument.

var NAME_MAX = 200
var TEXT_MAX = 20000
var KEYWORD_MAX = 64
var ARGUMENTS_MAX = 3            // [O] ref 02 §5.2
var CURSOR_MAX = 1               // [O]
var KEYWORDS = ["cursor", "clipboard", "uuid", "argument", "date", "time", "datetime", "day", "snippet", "calculator"]
var MODIFIERS = ["uppercase", "lowercase", "trim", "percent-encode", "json-stringify", "raw"]
var OFFSET = /^([+-])(\d+)([mhHdDMyY])$/
var CURSOR_MARK = "\u0000"

// ---------------------------------------------------------------- library

function list(doc) {
  return (doc && Array.isArray(doc.items) ? doc.items : []).filter(function(item) {
    return item && typeof item.id === "string" && typeof item.name === "string" && typeof item.text === "string"
  }).slice().sort(function(a, b) {
    var x = a.name.toLowerCase(), y = b.name.toLowerCase()
    return x < y ? -1 : (x > y ? 1 : (a.id < b.id ? -1 : 1))
  })
}

function get(doc, id) {
  return list(doc).filter(function(item) { return item.id === id })[0] || null
}

function byName(doc, name) {
  var wanted = String(name || "").trim().toLowerCase()
  return list(doc).filter(function(item) { return item.name.trim().toLowerCase() === wanted })[0] || null
}

function newId(doc, now) {
  var id = "sn-" + Number(now).toString(36)
  while (get(doc, id)) id += "x"
  return id
}

// Checks one {name, text, keyword?} against the library (other snippets
// may be named by {snippet name=…}).
function validate(doc, input, exceptId, deps) {
  var name = String(input && input.name != null ? input.name : "").trim()
  var text = String(input && input.text != null ? input.text : "")
  var keyword = String(input && input.keyword != null ? input.keyword : "").trim()
  if (!name) return { error: "A snippet needs a name" }
  if (name.length > NAME_MAX) return { error: "That name is too long" }
  if (!text.trim()) return { error: "A snippet needs some text" }
  if (text.length > TEXT_MAX) return { error: "That snippet is too long" }
  if (/\s/.test(keyword)) return { error: "A keyword cannot contain spaces" }
  if (keyword.length > KEYWORD_MAX) return { error: "That keyword is too long" }
  var others = list(doc).filter(function(item) { return item.id !== exceptId })
  if (others.some(function(item) { return item.name.trim().toLowerCase() === name.toLowerCase() })) return { error: "A snippet named " + name + " already exists" }
  if (keyword && others.some(function(item) { return item.keyword === keyword })) return { error: "The keyword " + keyword + " is already used" }
  var parsed = analyze(text, { items: others }, deps)
  if (parsed.error) return { error: parsed.error }
  return { error: "", item: { name: name, text: text, keyword: keyword } }
}

function save(doc, input, ctx, deps) {
  var checked = validate(doc, input, "", deps)
  if (checked.error) return { error: checked.error }
  var item = Object.assign({ id: newId(doc, ctx.now) }, checked.item, { createdAt: ctx.now, updatedAt: ctx.now })
  return { error: "", item: item, doc: { items: list(doc).concat([item]) } }
}

function update(doc, id, input, ctx, deps) {
  var current = get(doc, id)
  if (!current) return { error: "Snippet not found" }
  var checked = validate(doc, input, id, deps)
  if (checked.error) return { error: checked.error }
  var item = Object.assign({ id: id }, checked.item, { createdAt: current.createdAt, updatedAt: ctx.now })
  return { error: "", item: item, doc: { items: list(doc).map(function(it) { return it.id === id ? item : it }) } }
}

function remove(doc, id) {
  if (!get(doc, id)) return { error: "Snippet not found" }
  return { error: "", doc: { items: list(doc).filter(function(it) { return it.id !== id }) } }
}

// Raycast's export format [I]: [{name, text, keyword?}]. A row with the
// same name and text as a saved one is a duplicate. [D]
function importText(doc, raw, ctx, deps) {
  var rows
  try { rows = JSON.parse(String(raw || "")) } catch (e) { return { error: "That is not valid JSON" } }
  if (!Array.isArray(rows)) return { error: "Import expects a JSON array" }
  var next = { items: list(doc) }
  var added = 0, duplicates = 0, failed = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var label = row && typeof row.name === "string" && row.name.trim() ? row.name.trim() : "row " + (i + 1)
    if (!row || typeof row !== "object" || Array.isArray(row)) { failed.push(label); continue }
    if (list(next).some(function(it) { return it.name === String(row.name).trim() && it.text === String(row.text) })) { duplicates++; continue }
    var saved = save(next, row, { now: ctx.now + i }, deps)
    if (saved.error) { failed.push(label); continue }
    next = saved.doc
    added++
  }
  return { error: "", doc: next, added: added, duplicates: duplicates, failed: failed }
}

function exportList(doc) {
  return list(doc).map(function(item) {
    var row = { name: item.name, text: item.text }
    if (item.keyword) row.keyword = item.keyword
    return row
  })
}

// ----------------------------------------------------------- placeholders

// {kind, modifiers, attrs, ...}, {error}, or null for literal text.
function parsePlaceholder(inner, lexer) {
  var head = inner.split(/[ |]/)[0].toLowerCase()
  if (head === "selection") return { error: "Snippets cannot use {selection}" }
  if (KEYWORDS.indexOf(head) < 0) return null
  var tokens = lexer.tokenize(inner)
  for (var m = 0; m < tokens.modifiers.length; m++) {
    if (MODIFIERS.indexOf(tokens.modifiers[m]) < 0) return { error: "Unknown modifier " + tokens.modifiers[m] }
  }
  var attrs = {}, positional = []
  for (var w = 1; w < tokens.words.length; w++) {
    var word = tokens.words[w]
    var eq = word.quoted ? -1 : word.text.indexOf("=")
    if (eq > 0) attrs[word.text.slice(0, eq)] = word.text.slice(eq + 1)
    else positional.push(word.text)
  }
  var out = { kind: head, modifiers: tokens.modifiers, attrs: attrs }
  if (head === "argument") {
    out.name = attrs.name || "argument"
    out.defaultValue = attrs["default"] || ""
    out.options = attrs.options ? lexer.parseOptions(attrs.options) : []
  } else if (head === "clipboard") {
    var offset = attrs.offset === undefined ? 0 : Number(attrs.offset)
    if (!(offset >= 0 && Math.floor(offset) === offset)) return { error: "{clipboard offset} must be a whole number" }
    out.offset = offset
  } else if (head === "snippet") {
    out.name = String(attrs.name || positional[0] || "").trim()
    if (!out.name) return { error: "{snippet} needs a name" }
  } else if (head === "calculator") {
    out.expression = String(attrs.expression || positional[0] || "").trim()
    if (!out.expression) return { error: "{calculator} needs an expression" }
  } else if (head === "date" || head === "time" || head === "datetime" || head === "day") {
    // [O] Legacy {date "format" +1d}: a quoted format and offsets.
    var offsets = attrs.offset ? attrs.offset.trim().split(/\s+/) : []
    for (var q = 0; q < positional.length; q++) {
      if (/^[+-]\d/.test(positional[q])) offsets.push(positional[q])
      else if (!attrs.format) attrs.format = positional[q]
    }
    for (var o = 0; o < offsets.length; o++) if (!OFFSET.test(offsets[o])) return { error: "Bad date offset " + offsets[o] }
    out.offsets = offsets
  }
  return out
}

// Walks `text` once; `visit(placeholder)` returns its text or {error}.
function walk(text, visit, lexer) {
  var out = ""
  for (var i = 0; i < text.length;) {
    var start = text.indexOf("{", i)
    if (start < 0) { out += text.slice(i); break }
    out += text.slice(i, start)
    var end = lexer.placeholderEnd(text, start)
    if (end < 0) { out += "{"; i = start + 1; continue }
    var placeholder = parsePlaceholder(text.slice(start + 1, end), lexer)
    if (!placeholder) { out += text.slice(start, end + 1); i = end + 1; continue }
    if (placeholder.error) return { error: placeholder.error }
    var value = visit(placeholder)
    if (value && value.error) return { error: value.error }
    out += value
    i = end + 1
  }
  return { error: "", text: out }
}

// What pasting needs: arguments (merged by name, max 3), and checks that
// {cursor} appears at most once and that nested snippets exist and are flat.
function analyze(text, doc, deps) {
  var lexer = deps.lexer
  var args = [], cursors = 0
  var result = walk(String(text || ""), function(p) {
    if (p.kind === "cursor") cursors++
    if (p.kind === "snippet") {
      var nested = byName(doc, p.name)
      if (!nested) return { error: "No snippet named " + p.name }
      var inner = walk(nested.text, function(q) {
        return q.kind === "snippet" || q.kind === "argument" ? { error: p.name + " cannot be nested: it uses {" + q.kind + "}" } : ""
      }, lexer)
      if (inner.error) return { error: inner.error }
    }
    if (p.kind !== "argument") return ""
    var known = args.filter(function(a) { return a.name === p.name })[0]
    if (!known) args.push({ name: p.name, defaultValue: p.defaultValue, options: p.options })
    else {
      if (!known.defaultValue) known.defaultValue = p.defaultValue
      if (!known.options.length) known.options = p.options
    }
    return ""
  }, lexer)
  if (result.error) return { error: result.error }
  if (cursors > CURSOR_MAX) return { error: "A snippet can have only one {cursor}" }
  if (args.length > ARGUMENTS_MAX) return { error: "A snippet can have at most " + ARGUMENTS_MAX + " arguments" }
  return { error: "", arguments: args }
}

// Defaults, trimming, required arguments and options (an option matches its
// title or value, ignoring case), as for quicklinks.
function argumentValues(args, given) {
  var out = {}
  for (var i = 0; i < args.length; i++) {
    var arg = args[i]
    var text = String(given && given[arg.name] != null ? given[arg.name] : "").trim() || arg.defaultValue
    if (!text) return { error: arg.name + " is required" }
    if (arg.options.length) {
      var wanted = text.toLowerCase()
      var hit = arg.options.filter(function(o) { return o.title.toLowerCase() === wanted || o.value.toLowerCase() === wanted })[0]
      if (!hit) return { error: text + " is not one of " + arg.options.map(function(o) { return o.title }).join(", ") }
      text = hit.value
    }
    out[arg.name] = text
  }
  return { error: "", values: out }
}

// ctx: {now, values, names, clipboard(offset) -> string|null,
// calculate(expression) -> string|null, uuid() -> string}.
// Returns {text, cursorFromEnd}: how many characters after the {cursor}.
function expand(text, doc, ctx, deps) {
  var lexer = deps.lexer
  function fill(source, nested) {
    return walk(source, function(p) {
      var value
      switch (p.kind) {
        case "cursor": return nested ? "" : CURSOR_MARK
        case "argument": value = (ctx.values && ctx.values[p.name]) || ""; break
        case "uuid": value = ctx.uuid(); break
        case "clipboard":
          value = ctx.clipboard(p.offset)
          if (value === null || value === undefined) return { error: p.offset ? "Clipboard history has no text entry " + p.offset : "The clipboard has no text" }
          break
        case "calculator":
          value = ctx.calculate(p.expression)
          if (value === null || value === undefined) return { error: "Cannot calculate " + p.expression }
          break
        case "snippet":
          var nestedItem = byName(doc, p.name)
          if (!nestedItem) return { error: "No snippet named " + p.name }
          var inner = fill(nestedItem.text, true)
          if (inner.error) return inner
          value = inner.text
          break
        default: value = lexer.dateText(p, ctx)
      }
      value = String(value)
      for (var i = 0; i < p.modifiers.length; i++) {
        var m = p.modifiers[i]
        if (m === "uppercase") value = value.toUpperCase()
        else if (m === "lowercase") value = value.toLowerCase()
        else if (m === "trim") value = value.trim()
        else if (m === "json-stringify") value = JSON.stringify(value)
        else if (m === "percent-encode") value = encodeURIComponent(value)
      }
      return value
    }, lexer)
  }
  var result = fill(String(text || ""), false)
  if (result.error) return { error: result.error }
  var at = result.text.indexOf(CURSOR_MARK)
  var out = at < 0 ? result.text : result.text.slice(0, at) + result.text.slice(at + 1)
  // Left-arrow presses move by character, not UTF-16 unit.
  var after = at < 0 ? 0 : Array.from(result.text.slice(at + 1)).length
  return { error: "", text: out, cursorFromEnd: after }
}

// ---------------------------------------------------------- root search

function preview(text) {
  return String(text || "").replace(/\s+/g, " ").trim().slice(0, 120)
}

function toCandidate(item, doc, deps) {
  var parsed = analyze(item.text, doc, deps)
  return {
    id: "snippet:" + item.id,
    type: "command",
    kind: "snippet",
    title: item.name,
    subtitle: preview(item.text),
    keywords: item.keyword ? [item.keyword] : [],
    typeLabel: item.keyword ? item.keyword : "Snippet",
    glyph: "",                     // nf-fa-code
    snippetId: item.id,
    // Pills read {placeholder, required}; a default makes one optional.
    arguments: parsed.error ? [] : parsed.arguments.map(function(a) {
      return {
        name: a.name, defaultValue: a.defaultValue, options: a.options, required: !a.defaultValue,
        placeholder: a.options.length ? a.name + " ▾" : (a.defaultValue || a.name)
      }
    }),
    rootSearch: { when: "searching" }   // Search Snippets lists them all
  }
}

// The detail pane: the raw text with its keyword and dates pinned below.
function detail(item, relative) {
  var meta = [{ label: "Name", value: item.name }]
  if (item.keyword) meta.push({ label: "Keyword", value: item.keyword })
  meta.push({ label: "Characters", value: String(item.text.length) })
  if (item.updatedAt) meta.push({ label: "Modified", value: relative(item.updatedAt) })
  return { body: item.text, mono: true, metadata: meta, pinMetadata: true }
}

if (typeof module !== "undefined") {
  module.exports = {
    NAME_MAX: NAME_MAX,
    TEXT_MAX: TEXT_MAX,
    list: list,
    get: get,
    byName: byName,
    validate: validate,
    save: save,
    update: update,
    remove: remove,
    importText: importText,
    exportList: exportList,
    analyze: analyze,
    argumentValues: argumentValues,
    expand: expand,
    toCandidate: toCandidate,
    detail: detail
  }
}
