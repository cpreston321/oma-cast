const test = require("node:test")
const assert = require("node:assert/strict")
const S = require("../plugin/core/Snippets.js")
const Q = require("../plugin/core/Quicklinks.js")

const deps = { lexer: Q }
process.env.TZ = "America/New_York"
const NOW = Date.UTC(2026, 9, 26, 14, 30)   // Mon 26 Oct 2026, 10:30 in New York

function ctx(extra) {
  return Object.assign({
    now: NOW, values: {}, uuid: () => "uuid-1",
    clipboard: (offset) => ["latest", "older"][offset] ?? null,
    calculate: (expr) => (expr === "2+2" ? "4" : null)
  }, extra)
}

function library(...rows) {
  let doc = { items: [] }
  rows.forEach((row, i) => {
    const r = S.save(doc, row, { now: NOW + i }, deps)
    assert.equal(r.error, "", row.name)
    doc = r.doc
  })
  return doc
}

test("save validates names, keywords and placeholders", () => {
  const doc = library({ name: "Sig", text: "Best,\nChristian", keyword: ";sig" })
  assert.equal(S.save(doc, { name: "sig", text: "x" }, { now: 1 }, deps).error, "A snippet named sig already exists")
  assert.equal(S.save(doc, { name: "Other", text: "x", keyword: ";sig" }, { now: 1 }, deps).error, "The keyword ;sig is already used")
  assert.equal(S.save(doc, { name: "Spaced", text: "x", keyword: "a b" }, { now: 1 }, deps).error, "A keyword cannot contain spaces")
  assert.equal(S.save(doc, { name: "Empty", text: "  " }, { now: 1 }, deps).error, "A snippet needs some text")
  assert.equal(S.save(doc, { name: "Two", text: "{cursor}{cursor}" }, { now: 1 }, deps).error, "A snippet can have only one {cursor}")
  assert.equal(S.save(doc, { name: "Sel", text: "{selection}" }, { now: 1 }, deps).error, "Snippets cannot use {selection}")
  assert.equal(S.save(doc, { name: "Many", text: "{argument name=a}{argument name=b}{argument name=c}{argument name=d}" }, { now: 1 }, deps).error,
    "A snippet can have at most 3 arguments")
  assert.equal(S.save(doc, { name: "Ghost", text: "{snippet name=\"Nope\"}" }, { now: 1 }, deps).error, "No snippet named Nope")
})

test("update keeps the id and creation time; remove deletes", () => {
  const doc = library({ name: "Sig", text: "a" })
  const id = doc.items[0].id
  const updated = S.update(doc, id, { name: "Signature", text: "b" }, { now: NOW + 100 }, deps)
  assert.equal(updated.item.id, id)
  assert.equal(updated.item.createdAt, NOW)
  assert.equal(updated.item.updatedAt, NOW + 100)
  assert.deepEqual(S.remove(updated.doc, id).doc.items, [])
  assert.equal(S.remove(updated.doc, "nope").error, "Snippet not found")
})

test("unknown {words} stay literal, so code and JSON paste as written", () => {
  const doc = library()
  assert.equal(S.expand('function f() { return {a: 1} }', doc, ctx(), deps).text, 'function f() { return {a: 1} }')
  assert.equal(S.expand("{query} {name}", doc, ctx(), deps).text, "{query} {name}")
})

test("placeholders: clipboard history, uuid, dates, calculator, modifiers", () => {
  const doc = library()
  const r = (t, e) => S.expand(t, doc, ctx(e), deps)
  assert.equal(r("{clipboard} / {clipboard offset=1}").text, "latest / older")
  assert.equal(r("{clipboard offset=5}").error, "Clipboard history has no text entry 5")
  assert.equal(r("id {uuid}").text, "id uuid-1")
  assert.equal(r('{date format="yyyy-MM-dd" offset="+1d"}').text, "2026-10-27")
  assert.equal(r("{day}").text, "Monday")
  assert.equal(r('{calculator expression="2+2"}').text, "4")
  assert.equal(r('{calculator expression="nope"}').error, "Cannot calculate nope")
  assert.equal(r("{clipboard | uppercase}").text, "LATEST")
  assert.equal(r("{argument name=q | percent-encode}", { values: { q: "a b" } }).text, "a%20b")
  assert.equal(r("{argument name=q | json-stringify}", { values: { q: 'say "hi"' } }).text, '"say \\"hi\\""')
})

test("{cursor} is removed and reported as characters from the end", () => {
  const doc = library()
  const out = S.expand("Hi {cursor}, thanks 🎉", doc, ctx(), deps)
  assert.equal(out.text, "Hi , thanks 🎉")
  assert.equal(out.cursorFromEnd, ", thanks 🎉".length - 1, "the emoji counts as one character")
  assert.equal(S.expand("no cursor", doc, ctx(), deps).cursorFromEnd, 0)
})

test("nested snippets expand once; one that uses {snippet} or {argument} is refused", () => {
  const doc = library(
    { name: "Sig", text: "Christian {cursor}" },
    { name: "Mail", text: "Thanks!\n{snippet name=\"Sig\"}" },
    { name: "Asks", text: "{argument name=x}" }
  )
  assert.equal(S.expand(S.byName(doc, "Mail").text, doc, ctx(), deps).text, "Thanks!\nChristian ", "a nested {cursor} is dropped")
  assert.equal(S.save(doc, { name: "Bad", text: "{snippet name=Mail}" }, { now: 1 }, deps).error, "Mail cannot be nested: it uses {snippet}")
  assert.equal(S.save(doc, { name: "Bad", text: "{snippet name=Asks}" }, { now: 1 }, deps).error, "Asks cannot be nested: it uses {argument}")
})

test("arguments become pills; values fill defaults and check options", () => {
  const doc = library({ name: "Greet", text: '{argument name="who" default="team"} {argument name=tone options="Warm, Cool: chill"}' })
  const candidate = S.toCandidate(doc.items[0], doc, deps)
  assert.deepEqual(candidate.arguments.map((a) => [a.name, a.required, a.placeholder]), [["who", false, "team"], ["tone", true, "tone ▾"]])
  const args = S.analyze(doc.items[0].text, doc, deps).arguments
  assert.deepEqual(S.argumentValues(args, { tone: "cool" }).values, { who: "team", tone: "chill" })
  assert.equal(S.argumentValues(args, {}).error, "tone is required")
  assert.equal(S.argumentValues(args, { tone: "hot" }).error, "hot is not one of Warm, Cool")
})

test("import skips duplicates and bad rows; export is Raycast's shape", () => {
  const doc = library({ name: "Sig", text: "a", keyword: ";s" })
  const r = S.importText(doc, JSON.stringify([{ name: "Sig", text: "a" }, { name: "New", text: "b" }, { name: "", text: "c" }, 5]), { now: NOW }, deps)
  assert.equal(r.added, 1)
  assert.equal(r.duplicates, 1)
  assert.deepEqual(r.failed, ["row 3", "row 4"])
  assert.deepEqual(S.exportList(r.doc), [{ name: "New", text: "b" }, { name: "Sig", text: "a", keyword: ";s" }])
  assert.equal(S.importText(doc, "{", { now: 1 }, deps).error, "That is not valid JSON")
})

test("detail pins its metadata", () => {
  const doc = library({ name: "Sig", text: "abc", keyword: ";s" })
  const d = S.detail(doc.items[0], () => "Just now")
  assert.equal(d.pinMetadata, true)
  assert.deepEqual(d.metadata.map((m) => m.label), ["Name", "Keyword", "Characters", "Modified"])
})
