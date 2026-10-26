const test = require("node:test")
const assert = require("node:assert/strict")
const C = require("../plugin/core/Clipboard.js")

const HISTORY = JSON.stringify([
  { type: "text", text: "hello   world\nsecond line" },
  { type: "text", text: "   " },
  { type: "image", path: "/home/u/.local/state/omarchy/clipboard-images/1.png", mime: "image/png", capturedAt: "08:15" },
  { type: "text", text: "file:///home/u/My%20Notes.md" },
  { type: "text", text: "file:///a.txt\nfile:///b.txt" },
  { type: "bogus" },
  "a bare string"
])

test("parse keeps the file index, skips blanks and unknown types, and detects file URIs", () => {
  const entries = C.parse(HISTORY)
  assert.deepEqual(entries.map((e) => [e.kind, e.index]), [["text", 0], ["image", 2], ["file", 3], ["file", 4], ["text", 6]])
  assert.equal(entries[2].path, "/home/u/My Notes.md", "URIs are decoded")
  assert.deepEqual(entries[3].paths, ["/a.txt", "/b.txt"])
  assert.deepEqual(C.parse("nope"), [])
  assert.deepEqual(C.parse("{}"), [])
})

test("huge text is cut on a line break so no file URI is truncated", () => {
  const big = "x".repeat(C.MAX_TEXT - 10) + "\nfile:///" + "y".repeat(50)
  const [entry] = C.parse(JSON.stringify([{ type: "text", text: big }]))
  assert.equal(entry.kind, "text")
  assert.equal(entry.text.length, C.MAX_TEXT - 10)
})

test("previews collapse whitespace and describe images and files", () => {
  const [text, image, file, files] = C.parse(HISTORY)
  assert.equal(C.preview(text), "hello world second line")
  assert.equal(C.preview(image), "Screenshot from 08:15")
  assert.equal(C.preview(file), "My Notes.md")
  assert.equal(C.preview(files), "2 files")
})

test("filtering is a case-insensitive substring over text and previews", () => {
  const entries = C.parse(HISTORY)
  assert.deepEqual(C.filter(entries, "WORLD").map((e) => e.index), [0])
  assert.deepEqual(C.filter(entries, "screenshot").map((e) => e.index), [2])
  assert.deepEqual(C.filter(entries, "notes.md").map((e) => e.index), [3])
  assert.equal(C.filter(entries, "").length, entries.length)
})

test("detail and metadata read like Raycast's", () => {
  const [text, image, file] = C.parse(HISTORY)
  const d = C.detail(text)
  assert.equal(d.mono, true)
  assert.equal(d.pinMetadata, true, "the pane keeps metadata at the bottom")
  assert.equal(d.body, "hello   world\nsecond line")
  assert.deepEqual(d.metadata.map((m) => m.label), ["Type", "Characters", "Words", "Lines"])
  assert.equal(C.detail(image).image, image.path)
  assert.deepEqual(C.metadata(file).map((m) => m.value), ["File", "1 file", "/home/u/My Notes.md"])
})

test("paste goes through Omarchy's helpers by history index, or by path for images", () => {
  const [text, image] = C.parse(HISTORY)
  assert.deepEqual(C.pasteArgv(text, false), ["omarchy-clipboard-paste-text", "--shift-insert", "--history-index", "0"])
  assert.deepEqual(C.pasteArgv(text, true), ["omarchy-clipboard-paste-text", "--copy-only", "--history-index", "0"])
  assert.deepEqual(C.pasteArgv(image, false), ["omarchy-clipboard-paste-file", "image/png", image.path])
  assert.deepEqual(C.pasteArgv(image, true), ["omarchy-clipboard-paste-file", "--copy-only", "image/png", image.path])
})

test("rows carry the history index in their id", () => {
  const sections = C.sections(C.parse(HISTORY), "")
  assert.equal(sections.length, 1)
  assert.equal(sections[0].rows[1].candidate.id, "clipboard:2")
  assert.deepEqual(C.sections(C.parse(HISTORY), "zzz"), [])
})

test("the row limit caps the list", () => {
  const many = JSON.stringify(Array.from({ length: 30 }, (_, i) => ({ type: "text", text: "entry " + i })))
  assert.equal(C.sections(C.parse(many), "", 10)[0].rows.length, 10)
  assert.equal(C.sections(C.parse(many), "")[0].rows.length, 30)
})
