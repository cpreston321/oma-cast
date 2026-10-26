const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const Agent = require("../plugin/core/Agent.js")

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "oma-cast-agent-"))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const script = (name, source) => fs.writeFileSync(path.join(dir, name), "#!/bin/bash\n" + source, { mode: 0o700 })
  for (const tool of ["omarchy-agent", "omarchy-agent-prompt", "omarchy-launch-tui", "uwsm-app", "codex"]) script(tool, "exit 0\n")
  script("omarchy-default-agent", 'printf "%s" "${TEST_AGENT-codex}"\n')
  script("xdg-terminal-exec", '[[ $1 == --print-id ]] || exit 9\nprintf "%s" "${TEST_TERMINAL-foot.desktop}"\n')
  const env = { ...process.env, PATH: dir }
  return { dir, env, script, check: extra => spawnSync("/bin/bash", ["-c", Agent.CHECK_SCRIPT], { env: { ...env, ...extra }, encoding: "utf8" }) }
}

test("preflight accepts configured agents and terminal providers without starting a session", t => {
  const f = fixture(t)
  f.script("omarchy-agent", "exit 99\n")
  for (const terminal of ["foot.desktop", "com.mitchellh.ghostty.desktop", "kitty.desktop", "Alacritty.desktop"]) {
    const r = f.check({ TEST_TERMINAL: terminal })
    assert.equal(r.status, 0, r.stdout + r.stderr)
    assert.equal(r.stdout, "")
  }
})

test("preflight distinguishes missing tooling, default agent, installation and terminal", t => {
  const f = fixture(t)
  for (const [env, message] of [
    [{ TEST_AGENT: "" }, /Choose a default agent/],
    [{ TEST_AGENT: "not-installed" }, /default agent is not installed/],
    [{ TEST_TERMINAL: "" }, /default terminal/]
  ]) {
    const r = f.check(env)
    assert.equal(r.status, 1)
    assert.match(r.stdout, message)
  }
  fs.unlinkSync(path.join(f.dir, "omarchy-agent-prompt"))
  assert.match(f.check().stdout, /missing omarchy-agent-prompt/)
})

test("questions remain one literal argument, including CLI flags and shell metacharacters", t => {
  const f = fixture(t)
  f.script("omarchy-agent", '[[ $# == 2 && $1 == --prompt ]] || exit 8\nprintf "%s" "$2"\n')
  const marker = path.join(f.dir, "must-not-exist")
  for (const prompt of ["--inline", "--pick", "--prompt", "  Why?  ", 'Quotes: "hello" and \'hi\'', "line one\nline two 🚀", `$(touch ${marker}); \`touch ${marker}\`; >${marker}`]) {
    const argv = Agent.launchArgv(prompt)
    const r = spawnSync("/bin/bash", ["-c", 'exec "$@"', "bash", ...argv], { env: f.env, encoding: "utf8" })
    assert.equal(r.status, 0, r.stderr)
    assert.equal(r.stdout, prompt)
    assert.ok(!fs.existsSync(marker))
  }
})

test("empty, NUL and oversized prompts fail before any process starts", () => {
  for (const query of [null, undefined, "", " \n\t "]) assert.throws(() => Agent.launchArgv(query), /Type a question/)
  assert.throws(() => Agent.launchArgv("a\0b"), /NUL/)
  assert.throws(() => Agent.launchArgv("x".repeat(16385)), /characters/)
  assert.equal(Agent.launchArgv("x".repeat(16384))[2].length, 16384)
})

// ---- fork: agent choice, context, quick trigger, usage

test("launchCommand runs a chosen agent in a chosen folder, with every value literal", t => {
  const f = fixture(t)
  f.script("omarchy-agent", 'printf "%s|%s|%s" "$PWD" "$(omarchy-default-agent)" "$2"\n')
  f.script("omarchy-default-agent", 'echo claude\n')
  const runtime = fs.mkdtempSync(path.join(os.tmpdir(), "oma-cast-rt-"))
  // The fake tools first, then the system's bash, mkdir and chmod.
  const env = { ...f.env, PATH: f.dir + ":/usr/bin:/bin" }
  const run = (argv) => spawnSync(argv[0] === "bash" ? "/bin/bash" : path.join(f.dir, argv[0]), argv.slice(1), { env, encoding: "utf8" })
  const tricky = "why $(id); `x` 'q'"
  let r = run(Agent.launchCommand(tricky, { agent: "codex", cwd: os.tmpdir(), runtime }))
  assert.equal(r.stdout, os.tmpdir() + "|codex|" + tricky, r.stderr)
  r = run(Agent.launchCommand("hi", { cwd: "/does/not/exist", runtime }))
  assert.equal(r.stdout.split("|")[1], "claude", "no agent: the default")
  assert.deepEqual(Agent.launchCommand("hi"), ["omarchy-agent", "--prompt", "hi"], "plain when nothing is chosen")
  assert.throws(() => Agent.launchCommand("hi", { agent: "x; rm -rf /" }), /Unknown agent/)
  fs.rmSync(runtime, { recursive: true })
})

test("agents, context prompts, the quick trigger and usage", () => {
  assert.deepEqual(Agent.parseAgents("claude\ncodex\nnope\ndefault=claude\n"), { installed: ["claude", "codex"], defaultAgent: "claude" })
  assert.equal(Agent.parseAgents("default=\n").defaultAgent, "")
  assert.equal(Agent.agentName("cursor-agent"), "Cursor CLI")
  assert.equal(Agent.composePrompt("", { kind: "text", text: "TypeError: x is undefined" }), "Explain this.\n\n```\nTypeError: x is undefined\n```")
  assert.match(Agent.composePrompt("why?", { kind: "text", text: "a ``` b" }), /^why\?\n\n~~~~\n/, "a fence that can't close early")
  assert.equal(Agent.composePrompt("", { kind: "file", path: "/home/u/a.py" }), "Look at this file and explain what it is.\n\nFile: /home/u/a.py")
  assert.equal(Agent.quickQuestion("? how do I x", "?"), "how do I x")
  assert.equal(Agent.quickQuestion("?", "?"), "")
  assert.equal(Agent.quickQuestion("?x", "?"), null, "needs a space")
  assert.equal(Agent.quickQuestion("ai fix this", "ai"), "fix this")
  assert.equal(Agent.quickQuestion("? x", ""), null, "off")
  assert.equal(Agent.usageSummary({ limits: [{ label: "Session (5-hour)", percent: 0.12 }, { label: "Weekly (7-day)", percent: 0.02 }] }), "Session (5-hour) 12% · Weekly (7-day) 2%")
  assert.equal(Agent.usageSummary({}), "")
  assert.equal(Agent.usageSummary({ limits: [], todayPrompts: 3 }), "3 prompts today")
  assert.equal(Agent.usageSummary({ todayPrompts: 1 }), "1 prompt today")
})

test("AGENTS_SCRIPT counts Omarchy's install-on-first-use wrappers only once mise has them", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "oma-cast-agents-"))
  const write = (name, text) => { fs.writeFileSync(path.join(dir, name), text); fs.chmodSync(path.join(dir, name), 0o755) }
  try {
    write("pi", '#!/bin/bash\nmise use -g --quiet "pi" || exit 1\nexec mise x "pi" -- "pi" "$@"\n')
    write("omp", '#!/bin/bash\nmise use -g --quiet "github:can1357/oh-my-pi" || exit 1\n')
    write("codex", "#!/bin/sh\necho real\n")
    write("mise", '#!/bin/sh\n[ "$1" = where ] && [ "$2" = "github:can1357/oh-my-pi" ]\n')
    write("omarchy-default-agent", "#!/bin/sh\necho codex\n")
    const out = spawnSync("/bin/bash", ["-c", Agent.AGENTS_SCRIPT], { env: { PATH: dir + ":/usr/bin:/bin" }, encoding: "utf8" }).stdout
    assert.deepEqual(Agent.parseAgents(out), { installed: ["omp", "codex"], defaultAgent: "codex" })
  } finally {
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
