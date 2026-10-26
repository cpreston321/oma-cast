// Emoji picker (fork, ported from omalaunch's emoji extension). Pure logic:
// parse Omarchy's dataset, rank a query, and lay the result out as grid rows
// with section headers. Usage ("Frequently Used") is stored by the backend.

// The bundled dataset holds roughly 1.8k entries. Both caps exist so a
// malformed dataset cannot make the grid unbounded.
var MAX_DEFINITIONS = 8192
var MAX_RESULTS = 1000
var MAX_SEQUENCE = 32
var MAX_FREQUENT = 16
var MAX_USAGE = 256
var FREQUENT_SECTION = "Frequently Used"

// Unicode CLDR group order. Each entry names the first emoji of its group;
// the dataset is scanned in order, so emoji added inside a group are
// categorized without touching this list.
var GROUPS = [
  { label: "Smileys & Emotion", start: "😀" },
  { label: "People & Body", start: "👋" },
  { label: "Animals & Nature", start: "🐵" },
  { label: "Food & Drink", start: "🍇" },
  { label: "Travel & Places", start: "🌍" },
  { label: "Activities", start: "🎃" },
  { label: "Objects", start: "👓" },
  { label: "Symbols", start: "🏧" },
  { label: "Flags", start: "🏁" },
  { label: "Currency", start: "$" }
]

// Appended after Omarchy's dataset, so the last group boundary picks them up.
var CURRENCY = [
  { e: "$", k: "dollar sign usd united states" },
  { e: "€", k: "euro sign eur europe" },
  { e: "£", k: "pound sign sterling gbp britain" },
  { e: "¥", k: "yen sign yuan jpy cny japan china" },
  { e: "¢", k: "cent sign cents" },
  { e: "₹", k: "indian rupee sign inr india" },
  { e: "₽", k: "ruble sign rouble rub russia" },
  { e: "₩", k: "won sign krw korea" },
  { e: "₿", k: "bitcoin sign btc crypto" },
  { e: "₺", k: "turkish lira sign try turkey" },
  { e: "₪", k: "new shekel sign ils israel" },
  { e: "₫", k: "dong sign vnd vietnam" },
  { e: "₦", k: "naira sign ngn nigeria" },
  { e: "₱", k: "peso sign php philippines" },
  { e: "₴", k: "hryvnia sign uah ukraine" },
  { e: "₸", k: "tenge sign kzt kazakhstan" },
  { e: "₾", k: "lari sign gel georgia" },
  { e: "₼", k: "manat sign azn azerbaijan" },
  { e: "₭", k: "kip sign lak laos" },
  { e: "₮", k: "tugrik sign mnt mongolia" },
  { e: "₡", k: "colon sign crc costa rica" },
  { e: "₲", k: "guarani sign pyg paraguay" },
  { e: "₵", k: "cedi sign ghs ghana" },
  { e: "₨", k: "rupee sign rupees" },
  { e: "﷼", k: "rial sign saudi iran" },
  { e: "₣", k: "french franc sign" },
  { e: "₤", k: "lira sign" },
  { e: "₧", k: "peseta sign spain" },
  { e: "₯", k: "drachma sign greece" },
  { e: "₰", k: "german penny sign pfennig" },
  { e: "¤", k: "currency sign generic money" }
]

// Omarchy's dataset stores one space-joined keyword blob per emoji with no
// separate display name, so searching and captioning both derive from it.
function searchText(keywords) {
  return String(keywords || "").toLowerCase().replace(/[_\-\/]+/g, " ").replace(/\s+/g, " ").trim()
}

// Repeated words are common in the source keywords ("grinning face smile
// grinning happy"). Collapse them so the caption reads as a description.
function caption(keywords) {
  var words = searchText(keywords).split(" ")
  var seen = {}
  var out = []
  for (var i = 0; i < words.length; i++) {
    if (!words[i] || seen["$" + words[i]]) continue
    seen["$" + words[i]] = true
    out.push(words[i])
  }
  var text = out.join(" ")
  return text.charAt(0).toUpperCase() + text.slice(1)
}

function normalize(source, values, seen) {
  for (var i = 0; i < source.length && values.length < MAX_DEFINITIONS; i++) {
    var entry = source[i]
    if (!entry || typeof entry !== "object") continue
    var emoji = String(entry.e || entry.emoji || "")
    if (!emoji || emoji.length > MAX_SEQUENCE || seen["$" + emoji]) continue
    seen["$" + emoji] = true
    var keywords = String(entry.k || entry.keywords || entry.name || "")
    values.push({ emoji: emoji, search: searchText(keywords), caption: caption(keywords) })
  }
}

// Omarchy's emojis.json ([{e, k}]) plus the currency signs. Cross-set
// duplicates keep the first occurrence.
function parse(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = [] }
  var source = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.emojis) ? parsed.emojis : [])
  var values = []
  var seen = {}
  normalize(source, values, seen)
  normalize(CURRENCY, values, seen)
  return values
}

// Word-prefix matching, so "smi fac" finds "smiling face" while a term buried
// mid-word does not. A leading keyword scores higher than a trailing one
// because the source blobs put the primary name first. -1 is no match.
function matchScore(text, terms) {
  var words = String(text || "").split(" ")
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var best = 0
    for (var j = 0; j < words.length; j++) {
      if (words[j] === terms[i]) best = Math.max(best, j === 0 ? 4 : 3)
      else if (words[j].indexOf(terms[i]) === 0) best = Math.max(best, j === 0 ? 2 : 1)
    }
    if (best === 0) return -1
    total += best
  }
  return total
}

function terms(query) {
  var q = String(query || "").toLowerCase().trim()
  return q ? q.split(/\s+/) : []
}

function usageOf(usage, emoji) {
  var u = usage && usage["$" + emoji]
  return { count: u ? Math.max(0, Number(u.count) || 0) : 0, lastUsedAt: u ? Math.max(0, Number(u.lastUsedAt) || 0) : 0 }
}

// Match quality outranks history: a search for "cat" must not lead with a
// frequently used emoji that does not match.
function search(values, query, usage) {
  var t = terms(query)
  var rows = []
  for (var i = 0; i < values.length; i++) {
    var score = matchScore(values[i].search, t)
    if (score < 0) continue
    var u = usageOf(usage, values[i].emoji)
    rows.push({ entry: values[i], score: score, count: u.count, lastUsedAt: u.lastUsedAt, order: i })
  }
  rows.sort(function(a, b) {
    return (b.score - a.score) || (b.count - a.count) || (b.lastUsedAt - a.lastUsedAt) || (a.order - b.order)
  })
  return rows.slice(0, MAX_RESULTS).map(function(r) { return r.entry })
}

function frequent(values, usage, limit) {
  var out = []
  for (var i = 0; i < values.length; i++) {
    var u = usageOf(usage, values[i].emoji)
    if (u.count > 0) out.push({ entry: values[i], count: u.count, lastUsedAt: u.lastUsedAt, order: i })
  }
  out.sort(function(a, b) { return (b.count - a.count) || (b.lastUsedAt - a.lastUsedAt) || (a.order - b.order) })
  return out.slice(0, typeof limit === "number" ? Math.max(0, Math.min(64, limit)) : MAX_FREQUENT).map(function(r) { return r.entry })
}

// A group is everything from its first emoji up to the next group's. An
// out-of-order or missing boundary abandons grouping rather than mislabeling
// half the grid.
function groupLabels(values, groups) {
  if (!values.length || !groups.length) return null
  var starts = []
  var previous = -1
  for (var i = 0; i < groups.length; i++) {
    var at = -1
    for (var j = previous + 1; j < values.length; j++) if (values[j].emoji === groups[i].start) { at = j; break }
    if (at < 0) return null
    starts.push(at)
    previous = at
  }
  if (starts[0] !== 0) return null
  var labels = []
  var current = 0
  for (var k = 0; k < values.length; k++) {
    while (current + 1 < starts.length && k >= starts[current + 1]) current++
    labels.push(groups[current].label)
  }
  return labels
}

// Grid rows for the view: {kind: "section", title} or {kind: "cells", cells:
// [{emoji, caption}]}, at most `columns` cells each. A query is answered by one
// ranked run: category order would fight the ranking.
// frequentLimit: how many Frequently Used (0 hides the row); default 16.
function grid(values, query, usage, columns, frequentLimit) {
  var width = Math.max(1, Math.floor(columns) || 8)
  var rows = []
  function append(title, entries) {
    if (!entries.length) return
    if (title) rows.push({ kind: "section", title: title })
    for (var i = 0; i < entries.length; i += width)
      rows.push({ kind: "cells", cells: entries.slice(i, i + width).map(function(e) { return { emoji: e.emoji, caption: e.caption } }) })
  }
  if (terms(query).length) {
    append("", search(values, query, usage))
    return rows
  }
  append(FREQUENT_SECTION, frequent(values, usage, frequentLimit))
  // A frequently used emoji stays listed in its own category too, so browsing
  // a category never has holes in it.
  var labels = groupLabels(values, GROUPS)
  if (!labels) { append(rows.length ? "All" : "", values); return rows }
  var start = 0
  for (var k = 1; k <= values.length; k++) {
    if (k < values.length && labels[k] === labels[start]) continue
    append(labels[start], values.slice(start, k))
    start = k
  }
  return rows
}

// One more use of `emoji`; the least recently used fall off past MAX_USAGE.
function recordUsage(usage, emoji, nowMs) {
  var next = {}
  for (var key in (usage || {})) next[key] = usage[key]
  var u = usageOf(next, emoji)
  next["$" + emoji] = { count: u.count + 1, lastUsedAt: nowMs }
  var keys = Object.keys(next)
  if (keys.length > MAX_USAGE) {
    keys.sort(function(a, b) { return next[a].lastUsedAt - next[b].lastUsedAt })
    for (var i = 0; i < keys.length - MAX_USAGE; i++) delete next[keys[i]]
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    GROUPS: GROUPS,
    CURRENCY: CURRENCY,
    FREQUENT_SECTION: FREQUENT_SECTION,
    MAX_FREQUENT: MAX_FREQUENT,
    MAX_USAGE: MAX_USAGE,
    caption: caption,
    parse: parse,
    matchScore: matchScore,
    search: search,
    groupLabels: groupLabels,
    grid: grid,
    recordUsage: recordUsage
  }
}
