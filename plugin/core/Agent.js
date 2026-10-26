var FALLBACK_ID = "fallback:agent"

// The agents `omarchy-default-agent` knows, in its order, with its names.
var AGENTS = [
  { id: "pi", name: "Pi" }, { id: "omp", name: "Oh My Pi" }, { id: "opencode", name: "OpenCode" },
  { id: "claude", name: "Claude Code" }, { id: "codex", name: "Codex" }, { id: "crush", name: "Crush" },
  { id: "grok", name: "Grok" }, { id: "gemini", name: "Gemini" }, { id: "openclaw", name: "OpenClaw" },
  { id: "hermes", name: "Hermes" }, { id: "copilot", name: "GitHub Copilot" }, { id: "cursor-agent", name: "Cursor CLI" },
  { id: "muse", name: "Muse Code" }
]

function agentName(id) {
  var a = AGENTS.filter(function(x) { return x.id === id })[0]
  return a ? a.name : String(id || "")
}

function isAgent(id) {
  return AGENTS.some(function(a) { return a.id === id })
}

function checkPrompt(query) {
  var prompt = String(query === undefined || query === null ? "" : query)
  if (!prompt.trim()) throw new Error("Type a question first")
  if (prompt.indexOf("\u0000") >= 0) throw new Error("Questions cannot contain a NUL character")
  if (prompt.length > 16384) throw new Error("Keep the question under 16,385 characters")
  return prompt
}

function launchArgv(query) {
  return ["omarchy-agent", "--prompt", checkPrompt(query)]
}

// Omarchy's own launcher, with two fork options (opts):
//   agent: run this agent instead of the default. omarchy-agent asks
//     omarchy-default-agent which one to start, so a stand-in answering with
//     `agent` goes first on PATH for this launch; the saved default is untouched.
//   cwd:   start the session there (a file's folder), not Omarchy's default.
//   runtime: a private directory for the stand-in ($XDG_RUNTIME_DIR/oma-cast).
// Everything reaches bash as positional parameters, never as script text.
var LAUNCH_SCRIPT = [
  'dir=$1 agent=$2 runtime=$3 prompt=$4',
  '[[ -n $dir ]] && { cd -- "$dir" 2>/dev/null || cd -- "$HOME"; }',
  'if [[ -n $agent ]]; then',
  '  shim="$runtime/agent-$agent"',
  '  mkdir -p -- "$shim" && printf "#!/bin/sh\\necho %s\\n" "$agent" >"$shim/omarchy-default-agent" && chmod +x "$shim/omarchy-default-agent" || exit 1',
  '  PATH="$shim:$PATH"',
  'fi',
  'exec omarchy-agent --prompt "$prompt"'
].join("\n")

function launchCommand(query, opts) {
  var prompt = checkPrompt(query)
  var o = opts || {}
  var agent = o.agent && isAgent(o.agent) ? o.agent : ""
  if (o.agent && !agent) throw new Error("Unknown agent " + o.agent)
  if (!agent && !o.cwd) return ["omarchy-agent", "--prompt", prompt]
  return ["bash", "-c", LAUNCH_SCRIPT, "bash", String(o.cwd || ""), agent, String(o.runtime || "/tmp"), prompt]
}

// Ready-to-run checks; $1 names an agent to check instead of the default.
var CHECK_SCRIPT = [
  'for tool in omarchy-agent omarchy-agent-prompt omarchy-default-agent omarchy-launch-tui xdg-terminal-exec uwsm-app; do',
  '  command -v "$tool" >/dev/null 2>&1 || { printf "Agent launch unavailable: missing %s. Update Omarchy.\\n" "$tool"; exit 1; }',
  'done',
  'agent=${1:-}',
  'if [[ -z $agent ]]; then',
  '  agent=$(omarchy-default-agent) || { printf "Could not read the default agent\\n"; exit 1; }',
  '  [[ -n $agent ]] || { printf "Choose a default agent in Omarchy Settings first\\n"; exit 1; }',
  'fi',
  'if ! command -v "$agent" >/dev/null 2>&1; then',
  '  [[ -n ${1:-} ]] && printf "%s is not installed\\n" "$agent" || printf "Your default agent is not installed\\n"',
  '  exit 1',
  'fi',
  'terminal=$(xdg-terminal-exec --print-id 2>/dev/null) || { printf "Choose an installed default terminal in Omarchy Settings\\n"; exit 1; }',
  '[[ -n $terminal ]] || { printf "Choose an installed default terminal in Omarchy Settings\\n"; exit 1; }'
].join("\n")

// Prints the installed agents' ids, one per line, then the default as
// "default=<id>". Omarchy puts an install-on-first-use wrapper on PATH for
// every agent ("mise use -g <package>"); as omarchy-default-agent does, one
// counts only once mise has the package.
var AGENTS_SCRIPT = [
  'for agent in ' + AGENTS.map(function(a) { return a.id }).join(" ") + '; do',
  '  p=$(command -v "$agent" 2>/dev/null) || continue',
  '  if [[ ! -L $p ]] && grep -q "^mise use -g" "$p" 2>/dev/null; then',
  '    pkg=$(sed -n "s/^mise use -g[^\\"]*\\"\\([^\\"]*\\)\\".*/\\1/p" "$p" | head -n 1)',
  '    [[ -n $pkg ]] && mise where "$pkg" >/dev/null 2>&1 || continue',
  '  fi',
  '  echo "$agent"',
  'done',
  'echo "default=$(omarchy-default-agent 2>/dev/null)"'
].join("\n")

function parseAgents(output) {
  var installed = [], current = ""
  String(output || "").split("\n").forEach(function(line) {
    var l = line.trim()
    if (l.indexOf("default=") === 0) current = l.slice(8)
    else if (isAgent(l) && installed.indexOf(l) < 0) installed.push(l)
  })
  return { installed: installed, defaultAgent: isAgent(current) ? current : "" }
}

// The question for something you have open: a clipboard entry or selection
// (text) or a file (path). Without a question, ask for an explanation.
var CONTEXT_TEXT_MAX = 12000

function composePrompt(question, context) {
  var q = String(question || "").trim()
  var c = context || {}
  if (c.kind === "file") return (q || "Look at this file and explain what it is.") + "\n\nFile: " + c.path
  var text = String(c.text || "")
  if (text.length > CONTEXT_TEXT_MAX) text = text.slice(0, CONTEXT_TEXT_MAX) + "\n… (cut)"
  var fence = text.indexOf("```") >= 0 ? "~~~~" : "```"
  return (q || "Explain this.") + "\n\n" + fence + "\n" + text + "\n" + fence
}

// "? how do I…" with prefix "?": the question, or null when the query does
// not start with the prefix. "" turns the trigger off.
function quickQuestion(query, prefix) {
  var p = String(prefix || "")
  var q = String(query || "")
  if (!p || q.indexOf(p) !== 0) return null
  var rest = q.slice(p.length)
  if (rest && rest.charAt(0) !== " ") return null
  return rest.trim()
}

// "Session (5-hour) 12% · Weekly (7-day) 2%" from an Omarchy usage record
// (~/.local/state/omarchy/agents/usage/<id>.json), "3 prompts today" when it
// has no limits, or "".
function usageSummary(record) {
  var limits = record && Array.isArray(record.limits) ? record.limits : []
  // Agents without plan limits report activity only.
  if (!limits.length && record && typeof record.todayPrompts === "number")
    return record.todayPrompts === 1 ? "1 prompt today" : record.todayPrompts + " prompts today"
  return limits.filter(function(l) { return l && typeof l.percent === "number" && l.label }).slice(0, 3).map(function(l) {
    return l.label + " " + Math.round(l.percent * 100) + "%"
  }).join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    FALLBACK_ID: FALLBACK_ID, AGENTS: AGENTS, agentName: agentName, isAgent: isAgent,
    launchArgv: launchArgv, launchCommand: launchCommand, LAUNCH_SCRIPT: LAUNCH_SCRIPT,
    CHECK_SCRIPT: CHECK_SCRIPT, AGENTS_SCRIPT: AGENTS_SCRIPT, parseAgents: parseAgents,
    composePrompt: composePrompt, quickQuestion: quickQuestion, usageSummary: usageSummary
  }
}
