const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

// QML generates a `<name>Changed` signal for every property; a function with
// that name stops the whole file from loading ("Duplicate method name"), which
// the unit tests, being plain JS, would never see.
function qmlFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name)
    return e.isDirectory() ? qmlFiles(p) : e.name.endsWith(".qml") ? [p] : []
  })
}

test("no QML function shadows a property's change signal", () => {
  const root = path.join(__dirname, "..")
  const files = qmlFiles(path.join(root, "plugin")).concat(qmlFiles(path.join(root, "bar-button")))
  const clashes = []
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8")
    const props = new Set([...text.matchAll(/^\s*(?:readonly\s+|required\s+|default\s+)*property\s+[\w.<>]+\s+(\w+)/gm)].map((m) => m[1]))
    for (const m of text.matchAll(/^\s*function\s+(\w+)Changed\s*\(/gm)) {
      if (props.has(m[1])) clashes.push(path.relative(root, file) + ": " + m[1] + "Changed")
    }
  }
  assert.deepEqual(clashes, [])
})
