// Clipboard History (fork, ported from omalaunch's clipboard extension).
//
// Omarchy's clipboard capture writes ~/.local/state/omarchy/clipboard-history.json:
// a JSON array of {type:"text",text} and {type:"image",path,mime,capturedAt},
// newest first. oma-cast reads it and never writes it.
//
// Only a prefix of an entry is ever scanned or rendered: a single large paste
// otherwise costs hundreds of megabytes of string work on every keystroke.
// Pasting passes the history index to Omarchy's helper, which reads the full
// entry back itself, so nothing is lost and no clipboard content is ever put on
// a command line where a process listing could show it.

var MAX_TEXT = 8192
var MAX_ENTRIES = 500
var MAX_ROWS = 100
var MAX_BODY = MAX_TEXT

function fileUriPath(line) {
  var value = String(line || "").trim()
  if (value.indexOf("file://") !== 0) return ""
  var path = value.slice(7)
  if (path.indexOf("localhost/") === 0) path = path.slice(9)
  if (path.charAt(0) !== "/") return ""
  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(text) {
  var lines = String(text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = fileUriPath(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function baseName(path) {
  var parts = String(path || "").split("/")
  return parts[parts.length - 1]
}

// Entries keep their position in the file as `index`: the paste helpers take it.
function parse(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "[]")) } catch (e) { return [] }
  if (!Array.isArray(parsed)) return []
  var entries = []
  for (var i = 0; i < parsed.length && entries.length < MAX_ENTRIES; i++) {
    var value = parsed[i]
    if (typeof value === "string") value = { type: "text", text: value }
    if (!value || typeof value !== "object") continue
    var type = String(value.type || value.kind || "")
    if (type === "image") {
      if (!value.path) continue
      entries.push({ kind: "image", index: i, path: String(value.path), paths: [], mime: String(value.mime || "image/png"), capturedAt: String(value.capturedAt || ""), text: "" })
      continue
    }
    if (type !== "text") continue
    var text = String(value.text || "")
    if (!text.trim()) continue
    // Cut on a line break so a file:// URI never truncates into a bogus path.
    if (text.length > MAX_TEXT) {
      var cut = text.lastIndexOf("\n", MAX_TEXT)
      text = text.slice(0, cut > 0 ? cut : MAX_TEXT)
    }
    var paths = filePaths(text)
    entries.push({ kind: paths.length ? "file" : "text", index: i, path: paths.length === 1 ? paths[0] : "", paths: paths, mime: "text/plain", capturedAt: "", text: text })
  }
  return entries
}

function preview(entry) {
  if (entry.kind === "image") return (entry.mime === "image/png" ? "Screenshot" : "Image") + (entry.capturedAt ? " from " + entry.capturedAt : "")
  if (entry.kind === "file") return entry.paths.length === 1 ? baseName(entry.paths[0]) : entry.paths.length + " files"
  return String(entry.text || "").replace(/\s+/g, " ").trim()
}

// A remembered fragment is what people search a clipboard by, so this is a
// plain case-insensitive substring rather than the ranker.
function searchText(entry) {
  if (entry.kind === "image") return ("image screenshot " + entry.mime + " " + entry.capturedAt).toLowerCase()
  return (String(entry.text || "") + " " + preview(entry)).toLowerCase()
}

function filter(entries, query) {
  var needle = String(query || "").trim().toLowerCase()
  var out = []
  for (var i = 0; i < entries.length && out.length < MAX_ROWS; i++) {
    if (!needle || searchText(entries[i]).indexOf(needle) >= 0) out.push(entries[i])
  }
  return out
}

var GLYPHS = { text: "", file: "", image: "" }   // nf-fa-paste, file, image

function candidate(entry) {
  return {
    id: "clipboard:" + entry.index, type: "command", kind: "clipboard",
    title: preview(entry), subtitle: "", glyph: GLYPHS[entry.kind] || GLYPHS.text,
    typeLabel: entry.kind === "image" ? "Image" : (entry.kind === "file" ? (entry.paths.length === 1 ? "File" : "Files") : ""),
    historyIndex: entry.index, rootSearch: { when: "always" }
  }
}

function sections(entries, query) {
  var list = filter(entries, query)
  return list.length ? [{ id: "clipboard", title: "", rows: list.map(function(e) { return { candidate: candidate(e), record: null } }) }] : []
}

function count(n, singular) {
  return n + " " + (n === 1 ? singular : singular + "s")
}

// Label/value pairs in the order Raycast reads them: what it is, then how big,
// then where it came from.
function metadata(entry) {
  if (entry.kind === "image") {
    var image = [{ label: "Type", value: "Image" }, { label: "Format", value: entry.mime }]
    if (entry.capturedAt) image.push({ label: "Captured", value: entry.capturedAt })
    image.push({ label: "Path", value: entry.path })
    return image
  }
  if (entry.kind === "file") {
    var files = [{ label: "Type", value: entry.paths.length === 1 ? "File" : "Files" }, { label: "Count", value: count(entry.paths.length, "file") }]
    if (entry.paths.length === 1) files.push({ label: "Path", value: entry.paths[0] })
    return files
  }
  var text = String(entry.text || "")
  var lines = text.split(/\r?\n/).length
  var meta = [
    { label: "Type", value: "Text" },
    { label: "Characters", value: String(text.length) },
    { label: "Words", value: String(text.trim() ? text.trim().split(/\s+/).length : 0) }
  ]
  if (lines > 1) meta.push({ label: "Lines", value: String(lines) })
  return meta
}

// The detail pane: {body, mono, image, metadata}.
function detail(entry) {
  var body = entry.kind === "image" ? "" : (entry.kind === "file" ? entry.paths.join("\n") : String(entry.text || ""))
  return {
    body: body.length > MAX_BODY ? body.slice(0, MAX_BODY) : body,
    mono: entry.kind === "text",
    image: entry.kind === "image" ? entry.path : "",
    metadata: metadata(entry),
    // The detail pane keeps these at the bottom and scrolls the content.
    pinMetadata: true
  }
}

// argv for Omarchy's helpers. Images go through the file helper by path;
// text (and file URIs) by history index.
function pasteArgv(entry, copyOnly) {
  if (entry.kind === "image") return ["omarchy-clipboard-paste-file"].concat(copyOnly ? ["--copy-only"] : [], [entry.mime, entry.path])
  return ["omarchy-clipboard-paste-text"].concat(copyOnly ? ["--copy-only"] : ["--shift-insert"], ["--history-index", String(entry.index)])
}

// Omarchy opens an entry in its default app (an image viewer, an editor, …).
function openArgv(entry) {
  return ["omarchy-clipboard-open", "--history-index", String(entry.index)]
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_TEXT: MAX_TEXT,
    MAX_ROWS: MAX_ROWS,
    filePaths: filePaths,
    parse: parse,
    preview: preview,
    filter: filter,
    candidate: candidate,
    sections: sections,
    metadata: metadata,
    detail: detail,
    pasteArgv: pasteArgv,
    openArgv: openArgv
  }
}
