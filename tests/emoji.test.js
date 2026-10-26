const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const E = require("../plugin/core/Emoji.js")

const SAMPLE = JSON.stringify([
  { e: "😀", k: "grinning face smile grinning happy" },
  { e: "😺", k: "grinning cat smiling" },
  { e: "👋", k: "waving hand wave" },
  { e: "🐵", k: "monkey face" },
  { e: "🐱", k: "cat face pet" },
  { e: "😀", k: "duplicate is dropped" }
])
const GROUPS = [
  { label: "Smileys & Emotion", start: "😀" },
  { label: "People & Body", start: "👋" },
  { label: "Animals & Nature", start: "🐵" }
]

test("parse reads Omarchy's {e, k} entries, drops duplicates and appends currency signs", () => {
  const values = E.parse(SAMPLE)
  assert.equal(values.filter((v) => v.emoji === "😀").length, 1)
  assert.equal(values[0].caption, "Grinning face smile happy", "repeated keywords collapse")
  assert.equal(values.length, 5 + E.CURRENCY.length)
  assert.equal(values[5].emoji, "$")
  assert.deepEqual(E.parse("not json").map((v) => v.emoji), E.CURRENCY.map((c) => c.e))
})

test("matching is word-prefix, every term must match, and the leading keyword wins", () => {
  assert.equal(E.matchScore("grinning face smile", ["grin"]), 2)
  assert.equal(E.matchScore("grinning face smile", ["face"]), 3)
  assert.equal(E.matchScore("grinning face smile", ["rinning"]), -1, "mid-word terms do not match")
  assert.equal(E.matchScore("grinning face smile", ["grin", "dog"]), -1)
  const values = E.parse(SAMPLE)
  assert.deepEqual(E.search(values, "cat", {}).map((v) => v.emoji), ["🐱", "😺"])
})

test("usage breaks ties but never outranks match quality", () => {
  const values = E.parse(SAMPLE)
  let usage = E.recordUsage({}, "😺", 1000)
  usage = E.recordUsage(usage, "😺", 2000)
  assert.deepEqual(E.search(values, "cat", usage).map((v) => v.emoji), ["🐱", "😺"])
  assert.deepEqual(E.search(values, "grinning", usage).map((v) => v.emoji).slice(0, 2), ["😺", "😀"], "equal matches: the used one first")
  assert.deepEqual(E.search(values, "grinning", {}).map((v) => v.emoji).slice(0, 2), ["😀", "😺"], "no usage: dataset order")
  assert.deepEqual(E.search(values, "smil", usage).map((v) => v.emoji).slice(0, 2), ["😺", "😀"])
})

test("recordUsage counts uses and forgets the least recent past the cap", () => {
  let usage = {}
  for (let i = 0; i < E.MAX_USAGE + 5; i++) usage = E.recordUsage(usage, "x" + i, i)
  assert.equal(Object.keys(usage).length, E.MAX_USAGE)
  assert.equal(usage["$x0"], undefined)
  usage = E.recordUsage(usage, "x10", 9999)
  assert.deepEqual(usage["$x10"], { count: 2, lastUsedAt: 9999 })
})

test("grid rows are cut to the column count and a query has no headers", () => {
  const values = E.parse(SAMPLE)
  const rows = E.grid(values, "face", {}, 2)
  assert.ok(rows.every((r) => r.kind === "cells" && r.cells.length <= 2))
  assert.deepEqual(rows.flatMap((r) => r.cells.map((c) => c.emoji)), ["😀", "🐵", "🐱"])
})

test("group boundaries out of order abandon grouping instead of mislabeling", () => {
  const values = E.parse(SAMPLE)
  assert.equal(E.groupLabels(values, [GROUPS[1], GROUPS[0]]), null)
  assert.deepEqual(E.groupLabels(values, GROUPS).slice(0, 5), ["Smileys & Emotion", "Smileys & Emotion", "People & Body", "Animals & Nature", "Animals & Nature"])
})

const DATASET = (process.env.OMARCHY_PATH || "/usr/share/omarchy") + "/shell/plugins/emojis/emojis.json"

test("Omarchy's dataset groups into every CLDR section plus Currency", { skip: !fs.existsSync(DATASET) && "Omarchy's emojis.json is not installed" }, () => {
  const values = E.parse(fs.readFileSync(DATASET, "utf8"))
  assert.ok(values.length > 1500)
  const usage = E.recordUsage({}, "😀", 1)
  const rows = E.grid(values, "", usage, 10)
  const titles = rows.filter((r) => r.kind === "section").map((r) => r.title)
  assert.deepEqual(titles, [E.FREQUENT_SECTION].concat(E.GROUPS.map((g) => g.label)))
  const currency = rows.slice(rows.findIndex((r) => r.title === "Currency") + 1).flatMap((r) => r.cells.map((c) => c.emoji))
  assert.equal(currency[0], "$")
})
