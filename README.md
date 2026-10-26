<div align="center">

# oma-cast

**A Raycast-esque launcher for [Omarchy](https://omarchy.org).**
It learns what you use, searches your apps and every Omarchy action, and looks like it shipped with your theme.

<img src="docs/screenshots/hero.png" alt="oma-cast showing suggestions for apps and Omarchy commands" width="760">

</div>

---

## Why

Omarchy's built-in menu is great at what it does. oma-cast adds what Raycast users miss on Linux:

* **Learns your habits.** Results are ranked with a port of Raycast's root-search algorithm, plus frecency and learned search terms. The things you actually use float to the top, and if you type `ff` and pick Firefox, `ff` keeps meaning Firefox.
* **One search for everything.** Your apps, all ~400 Omarchy menu actions (with breadcrumbs and live ✓ state), web-search fallbacks, and an explicit hand-off to your default coding agent.
* **Your shortcuts.** Give anything an alias, pin favorites, and hide the commands you never touch.
* **Keyboard-first.** A Ctrl+K action panel, Ctrl+1–9 quick picks, search history on ↑, section jumping, and emacs-style navigation.
* **Native to Omarchy.** It runs inside `omarchy-shell` as a plugin, with no Electron, no Node and no extra daemons. It opens in about 40 ms and follows your theme live when you run `omarchy theme set`.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/search.png" alt="Searching 'screen' shows Omarchy actions with breadcrumbs"></td>
    <td width="50%"><img src="docs/screenshots/actions.png" alt="The Ctrl+K action panel"></td>
  </tr>
  <tr>
    <td align="center"><b>Every Omarchy action, with breadcrumbs</b></td>
    <td align="center"><b>Ctrl+K: actions for any result</b></td>
  </tr>
</table>

<p align="center">
  <img src="docs/screenshots/fallbacks.png" alt="Web-search fallbacks under the results" width="49%">
</p>
<p align="center"><b>No match? Send the query to Google or DuckDuckGo</b></p>

### Follows your Omarchy theme

There's no theme config. oma-cast binds to Omarchy's own colours, so it changes the moment you switch themes.

<img src="docs/screenshots/themes.png" alt="oma-cast in Tokyo Night, Gruvbox, Rose Pine, Flexoki Light, Everforest and Osaka Jade">

## Install

Requires Omarchy 4 (Hyprland 0.56+, `omarchy-shell`) and `socat`, which Omarchy already ships.

```sh
git clone https://github.com/typecraft-dev/oma-cast.git
cd oma-cast
bin/oma-cast install          # link the plugin into omarchy-shell and the CLI into ~/.local/bin
oma-cast setup hyprland       # bind Alt+Space
oma-cast doctor               # check everything is wired up
```

Press **Alt+Space**. Super+Space stays the Omarchy menu. You can change the launcher binding in `~/.config/hypr/oma-cast.lua`.

To remove it: `oma-cast uninstall`.

## Ask your default agent

Type a question, select **Ask default agent** under the web-search fallbacks,
and press Enter. **Ctrl+Alt+Enter** sends the current root-search text directly.
This opens a new session with your question in Omarchy's configured default
agent and terminal (Foot, Ghostty, Kitty or Alacritty).

The action checks your setup first. Missing agent/terminal setup leaves the
launcher open with your question and an error. Closing the launcher during the
check cancels the pending hand-off. Normal app search and Enter selection keep
working as before; typing alone never submits a question.

Requires an Omarchy version with `omarchy-agent-prompt` and
`omarchy-agent --prompt` (verified against `quattro` revision `3ac4365`). Select
your defaults in Omarchy Settings. Agent authentication, accounts, approval
behaviour, session working directory and terminal selection remain owned by
Omarchy and the agent CLI. oma-cast does not store the question in search history,
read credentials, or make model API calls. Successful preflight checks establish
launch prerequisites, not successful sign-in or a running terminal; those still
need live desktop validation.

## Emoji, clipboard history and window layouts

Ported from [omalaunch](https://github.com/cpreston321/omalaunch). Each one is a
root command, so you can alias or favorite it like anything else.

* **Search Emoji.** A grid of Omarchy's emoji set plus currency signs, grouped
  by category with a *Frequently Used* row on top. Search matches word
  prefixes (`smi fac` finds smiling faces). Arrow keys move around the grid,
  `Ctrl+↑/↓` jumps between groups, `↵` pastes and `Ctrl+↵` copies.
* **Clipboard History.** Reads Omarchy's own clipboard history. Shows text, files
  and screenshots with a detail pane beside the list. `↵` pastes, `Ctrl+↵` copies
  and `Ctrl+Shift+↵` opens the entry. oma-cast never writes the history.
* **Window Layouts.** Save the current window arrangement and restore it later,
  with a preview of each saved layout. Saved layouts also appear in root search
  while you type (`gaming` → *Gaming*). `↵` applies, `Ctrl+↵` applies and launches
  missing apps, and the rest (overwrite, rename, delete, edit in the
  [layout designer](https://github.com/cpreston321/omalaunch-layout-designer))
  are in `Ctrl+K`. Layouts live in `~/.local/state/omarchy/omalaunch-layouts`, so
  ones saved with omalaunch carry over. Needs `python3`.
* **omalaunch user extensions.** Action entries in
  `~/.config/omarchy/omalaunch/extensions.d` (static `.json` files or a
  `provider` executable) show up in root search while you type, e.g. a camera
  from a UniFi provider. Other omalaunch modes aren't supported.

## Snippets

**Search Snippets** lists them with a preview; a snippet also turns up in
root search by its name or keyword. `↵` pastes, `Ctrl+↵` copies, `Ctrl+E`
edits and `Ctrl+D` deletes. **Create Snippet** (or Settings → Snippets) has
a multi-line editor that checks the text as you type.

Placeholders follow Raycast's: `{cursor}` (the caret lands there after
pasting), `{clipboard}` / `{clipboard offset=1}` (from clipboard history),
`{argument name="who" default="team"}` (up to three, shown as pills),
`{date format="yyyy-MM-dd" offset="+1d"}`, `{time}`, `{datetime}`, `{day}`,
`{uuid}`, `{calculator expression="2+2"}`, `{snippet name="Signature"}`, and
the modifiers `| uppercase`, `| lowercase`, `| trim`, `| percent-encode`,
`| json-stringify`. Any other `{word}` stays as written, so code pastes
untouched. Snippets expand from the launcher only: typing a keyword in
another app does nothing (that needs input-device access).

Import and export use Raycast's JSON format, `[{name, text, keyword?}]`.

## Settings

**oma-cast Settings** in root search, `Ctrl+,` in the launcher, or
`oma-cast settings [tab]`. Tabs: General (window mode, text size, Esc,
return-to-root delay, navigation keys, search sensitivity), Commands
(every command's alias and on/off switch, including ones you disabled),
Snippets, Quicklinks and Calculator (currency rates, clock format, rem
size, work-day hours, history). `Ctrl+1`…`5` switch tabs, `Ctrl+S` saves,
`Esc` closes.

### Bar button and Super+Space

`oma-cast install-button` puts an Omarchy logo at the left of the bar that
opens oma-cast. It is a separate plugin (`bar-button/`) copied in as plain files,
because Qt won't load a bar widget through the symlinked plugin folder. To open
oma-cast with Super+Space instead of the Omarchy menu, add this to
`~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "oma-cast", hl.dsp.global("oma-cast:toggle"))
```

Keep `omarchy.menu` enabled: the theme, background and apps keys and Omarchy's
scripts still open its routes.

## Keyboard

| Key | Does |
|---|---|
| `↵` / `Ctrl+↵` / `Ctrl+Shift+↵` | Run the first, second or third action |
| `Shift+↵` | Open a new window of an app (`↵` switches to the one already open) |
| `Ctrl+K` | Open the action panel |
| `Super+V` / `Ctrl+V` / `Ctrl+Shift+V` / `Shift+Insert` | Paste text into the query (also accepts clipboard-history selections) |
| `Ctrl+Alt+↵` | Ask the default agent using the current root-search text |
| `Ctrl+1`…`9` | Pick a result |
| `↑` on an empty search | Search history |
| `Ctrl+↑` / `Ctrl+↓` | Jump between sections |
| `Ctrl+N` / `Ctrl+P` | Next / previous |
| `Ctrl+Shift+F` | Add to favorites (`Ctrl+Alt+↑↓` to reorder) |
| `Ctrl+Shift+C` | Copy |
| `Tab` / `Shift+Tab` | Move into and between a quicklink's arguments |
| `Ctrl+E` / `Ctrl+D` | Edit / delete a quicklink |
| `Alt+Shift+D` | Disable a command |
| `Esc` / `Shift+Esc` | Back / back to root |
| `Ctrl +` / `Ctrl −` / `Ctrl 0` | Zoom |

## CLI

```sh
oma-cast toggle | show | hide
oma-cast run <commandId>         # e.g. app:com.mitchellh.ghostty, omarchy:style.theme
oma-cast call <method> [json]    # call any backend method
oma-cast doctor
```

## Roadmap

oma-cast is early. Search, ranking and the Omarchy integration are done. Coming next:

- [x] Settings window
- [ ] Script Commands
- [x] Quicklinks
- [x] Calculator
- [x] Clipboard history
- [x] Snippets (from the launcher; keyword expansion in other apps not yet)
- [ ] Running Raycast extensions built from the open-source [`raycast/extensions`](https://github.com/raycast/extensions) repo
- [ ] Window management
- [ ] Importing your `.rayconfig` from macOS

The full plan is in [`SPEC.md`](SPEC.md).

## Development

```sh
node --test tests/*.test.js # unit tests, no npm install needed
tests/smoke.sh            # live checks against the running shell
oma-cast dev          # reload on every save
```

Quickshell caches QML for the life of the process, so run `oma-cast reload` after editing anything under `plugin/`. See [`CLAUDE.md`](CLAUDE.md) for the layout and conventions.

## Notes

oma-cast is an independent, clean-room project. It isn't affiliated with or endorsed by Raycast, and it contains no Raycast code or assets. It never contacts Raycast's servers and has no telemetry. Its agent action explicitly hands your question to Omarchy's existing coding-agent launcher; it provides no embedded AI runtime.
