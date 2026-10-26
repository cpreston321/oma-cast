# CLAUDE.md

This repo is a clean-room rebuild of **Raycast for Linux**. The first target is **Omarchy**: Arch Linux + Hyprland, plus Omarchy's own scripts, themes and bindings. The behaviour and interfaces come from a static reverse-engineering pass over Raycast 2.8.2 on macOS, done with the `reverse-engineer-anything` skill. This repo holds that pass's results and no Raycast code.

## Read these first

| File | What it is | When to read it |
|---|---|---|
| `SPEC.md` | **The plan.** Architecture, IPC contract, platform matrix, data layer, root-search algorithm, feature catalog, extension runtime, frontend, `.rayconfig` import, phased build plan with acceptance checks. | Before any work. Re-read the relevant section before each phase. |
| `reference/01-host-ipc.md` | Native host: window model, ~408 host capabilities (§4.1), WebView bridge, host↔backend wire protocol, helper processes, a Linux mapping for each (§4.3). | Phase 1 (window), Phase 5 (supervisor, for the Node extension host), Phase 6 (WM) |
| `reference/02-backend.md` | Backend service map and RPC methods, DB engine, **root-search ranking (§4)**, frecency (§4.6), clipboard (§5.1), snippet placeholder grammar (§5.2), quicklinks (§6), calculator, indexer. | Phases 1–4, 7 |
| `reference/03-extensions.md` | `@raycast/api` runtime: worker model, reconciler, **render-tree JSON schema (§2.4)**, API→RPC table (§3.2), manifest (§4), Script Commands (§5), install pipeline (§6), Icon enum (App. A). | Phase 2 (script commands), Phase 5 |
| `reference/04-frontend-features.md` | **Built-in command catalog (§1, App. A)**, launcher UI anatomy (§2), default shortcuts (§2.8), settings pages (§3, App. B/C), themes and design tokens (§4). | Phase 1 onward, every UI task |
| `reference/05-data-config.md` | On-disk layout, DB encryption, reconstructed schema, `.rayconfig` format (§5), XDG mapping (§8). | Phase 0 (paths, DB), Phase 8 (import) |
| `reference/schema-nonai.sql` | Raycast's non-AI DDL, reconstructed. **Reference only.** The clone uses the simpler schema in `SPEC.md §6.4`. | When you need a field Raycast stores |
| `reference/backend-methods-nonai.txt` | Every non-AI backend RPC method name. **Do not implement all of them.** Reuse the names for what each phase needs. | When naming an IPC method |

Spec legend: **[O]** observed in Raycast, **[I]** inferred, **[D]** design decision for this clone. [O] is ground truth for behaviour. [D] may be changed if you have a reason; note the change in `SPEC.md`.

## Ground rules (from SPEC.md §0, non-negotiable)

1. **Clean room.** Never copy, bundle or redistribute anything from `Raycast.app` (JS, icons, fonts, `.node` modules). Allowed: the public npm `@raycast/api` / `@raycast/utils` packages (check the license of the pinned version) and the MIT `raycast/extensions` repo.
2. **Never call `*.raycast.com`.** No store, account, sync, telemetry or currency APIs. Build extensions from a local `raycast/extensions` clone.
3. **No telemetry.** No Sentry, no PostHog.
4. **No embedded AI features.** The fork's user-authorized exception is an explicit hand-off of root-search text to Omarchy's existing default-agent terminal launcher (SPEC §2.0). No model API, credential handling or automatic submission while typing. Other built-ins remain non-AI.
5. **Port the root-search ranker exactly** from `reference/02-backend.md §4.2–4.5`. Do not substitute fzf, nucleo or fuse.js.

## How to work

- Build **phase by phase** following `SPEC.md §12` (Phase 0 → 9). A phase is done only when its **Accept** checks pass. Then move on.
- After each phase, update the **Status** section at the bottom of this file: what works, what's stubbed, and any deviations from the spec.
- If the reference docs don't answer a question, choose a sensible value, mark it `[I]` or `[D]` in a code comment, and keep going. Raycast.app is not on the Omarchy machine. Re-running the reverse-engineering only works on the Mac where `/Applications/Raycast.app` lives.
- The working name is **`oma-cast`**: plugin id `typecraft.oma-cast`, CLI `oma-cast`, IPC target `oma-cast`, layer namespace `oma-cast`, URL scheme `oma-cast://` (later). Also register `raycast://` for extension deep links (SPEC §5.5).

## Architecture: an Omarchy shell plugin (SPEC §2.0)

oma-cast runs **inside `omarchy-shell`**, Omarchy's long-lived Quickshell process, as the plugin `typecraft.oma-cast`. That is how Omarchy builds its own menu, emoji picker and clipboard overlays. **Keep external dependencies near zero:** QML and plain JS only, using what Omarchy already ships (Quickshell, Qt, bash, socat, Hyprland). No Tauri, Node runtime, npm packages or native modules without asking first. The Tauri/Node design in SPEC §2 is kept for reference only.

To learn the host, read the shell's own code in `$OMARCHY_PATH/shell/` (`/usr/share/omarchy/shell`):
- `shell.qml`: plugin loading, `summon`/`hide`/`toggle`, and the scoped `shell` API
- `plugins/menu/Menu.qml`: the Omarchy launcher/menu
- `plugins/emojis/Emojis.qml`: a small overlay plugin
- `services/AppLibrary.qml` + `AppSearch.js`: desktop entries, icons, `uwsm-app -- gtk-launch` launching
- `Commons/{Style,Color,Util}.qml` (Omarchy 4.0.x has no `Ui/OverlayWindow`; overlays are a `PanelWindow` on `WlrLayer.Overlay`)
- `default/agents/skills/omarchy/plugins.md`: plugin safety rules. Use `textFormat: Text.PlainText` for any dynamic text.

## Repo layout

```
SPEC.md, reference/      # the spec
plugin/                  # the Omarchy shell plugin (what gets linked into ~/.config/omarchy/plugins/)
  manifest.json          #   id typecraft.oma-cast, kind "menu" (so the shell passes shell.appLibrary), keepLoaded
  Launcher.qml           #   entry point: open()/close() from the shell, IpcHandler "oma-cast", GlobalShortcut oma-cast:toggle
  Backend.qml            #   in-process backend: paths, config.json, stores, method registry, notifications
  ui/                    #   launcher surface and (later) views
  services/              #   QML services that do I/O (JsonStore, OmarchyMenuSource; later clipboard, …)
  core/*.js              #   pure logic, no Qt imports: shared by QML and node tests (module.exports guard)
                         #   Ranker, Frecency (ref 02 §4, port exactly), OmarchyMenu, RootSearch, FileSearch, Schema, Migrate, Rpc, Paths, Log
bin/oma-cast             # bash CLI
tests/*.test.js          # node --test unit tests for plugin/core (ranker, frecency, Omarchy menu, root search, …)
tests/smoke.sh           # live acceptance check against the running shell
```

Rules for `plugin/core/*.js`: one self-contained file per module (QML `import "x.js"` and node `require` must both work, so a module never imports another one). Expose functions through the `if (typeof module !== "undefined") module.exports = …` guard. QML wires the modules together.

## Commands

```sh
node --test tests/*.test.js   # unit tests (node's built-in runner; no npm install)
mise x act@latest -- act push   # run .github/workflows/ci.yml locally in Docker (.actrc maps the WarpBuild label)
tests/smoke.sh               # live checks: doctor, IPC, toggle latency (<100 ms). Shows/hides the launcher, never types.
omarchy plugin validate plugin

bin/oma-cast install         # link plugin into ~/.config/omarchy/plugins, enable it, link CLI into ~/.local/bin
bin/oma-cast reload          # pick up QML/JS edits (see "Reloading" below)
bin/oma-cast dev             # reload on every save under plugin/ (needs inotifywait)
bin/oma-cast uninstall

oma-cast toggle | show | hide
oma-cast run <commandId>             # Phase 1+
oma-cast call <method> [json]        # any backend method, e.g. oma-cast call system.info
oma-cast doctor
oma-cast setup hyprland              # writes ~/.config/hypr/oma-cast.lua (Alt+Space) and requires it from hyprland.lua

qs log -n -p "$OMARCHY_PATH/shell" -t 50    # shell log; our lines start with [oma-cast]
```

**Reloading.** Quickshell keeps every QML/JS file it has read, keyed by path, for the life of the process, and the shell's inotify watch doesn't follow the symlink into this repo. So editing files under `plugin/` changes nothing until `oma-cast reload` re-links the plugin under a fresh `typecraft.oma-cast.dev-<ns>` path. Always reload, then check `qs log` for QML errors, before concluding a change works. A QML error shows up as "Type X unavailable" plus the real cause on the next line. Names that clash with JS globals (such as `escape`) are "Illegal method name".

## Running on Omarchy

Check each of these on the machine instead of assuming it; Omarchy changes often.

- **Hyprland config is Lua** (Hyprland 0.56). `~/.config/hypr/hyprland.lua` `require`s `default.hypr.omarchy` and the user's `hypr.bindings` etc. Bindings use `o.bind("ALT + SPACE", "desc", dispatcher)`. `oma-cast setup hyprland` writes only `~/.config/hypr/oma-cast.lua` and appends one `require("hypr.oma-cast")`. Never edit Omarchy's files.
- **Hotkey.** Super+Space is the Omarchy menu and Super+Alt+Space is the dock's app grid. oma-cast defaults to **Alt+Space** through `hl.dsp.global("oma-cast:toggle")`, so the plugin's GlobalShortcut fires with no process spawn. Users can change their binding in `oma-cast.lua`; never force a Super+Space swap.
- **IPC.** `omarchy-shell <target> <fn> args…` answers over the shell's socket (needs `socat`), falling back to `qs ipc`. Our target is `oma-cast`. `IpcHandler` (Quickshell.Io; 4.0.x dropped `ShellIpc`) functions must have typed params and return a string.
- **Theme.** Bind colours to `Commons.Color.menu.*` and sizes to `Style.*`. They follow `omarchy theme set` live; no theme parsing.
- **App launching.** Use `shell.appLibrary.launch(id, name)`. It goes through `uwsm-app -- gtk-launch`, sends terminal apps to `omarchy-launch-tui`, and shows Omarchy's launch OSD. The shell only provides `appLibrary` to `menu`-kind plugins.
- **Terminals and paste.** Alacritty/Ghostty/Kitty need Ctrl+Shift+V (SPEC §5.3). Read the class from `hyprctl activewindow -j`.
- **Notifications** go to the Omarchy shell's notification service (`org.freedesktop.Notifications`). The bar has a tray widget (SNI).
- **Snippet expansion** needs the `input` group or a uinput udev rule. Keep it opt-in; `oma-cast doctor` explains it.
- **Testing on the live desktop.** Don't synthesize keystrokes (`wtype`) unless the launcher is already mapped and focused. Keys sent within about 25 ms of `show` go to the window underneath, which is usually the terminal running Claude.

## Status

Keybindings search (2026-10-22): native Search Keybindings view, live Omarchy
binding source, root-search shortcut results, keycap accessories, and copy
shortcut actions. `tests/keybindings.test.js` covers parsing, stable IDs,
custom/alternate bindings, chord and fuzzy queries, and literal markup data.

Renamed **raylinux → oma-launcher → oma-cast** on 2026-10-19 (plugin `typecraft.oma-cast`, CLI `oma-cast`, IPC target and global shortcut `oma-cast:toggle`, XDG dirs `oma-cast`). The app icon is Omarchy's logo: glyph `\ue900` in the `omarchy` font, the same one the bar's menu button uses.

**Phase 1 (Quickshell build): done**, with the gaps listed below. **Phase 0: done.** Omarchy 4.0.0.alpha, Quickshell 0.3.2, Hyprland 0.56.2.

Works:
- **Root search** ported from ref 02 §4.2–4.6 (`core/Ranker.js`, `core/Frecency.js`, golden tests). Sections (`core/RootSearch.js`):
  - empty root: Favorites, Suggestions (frecency > 1, top 6), Commands, Applications
  - query: Results, Files, then `Use "<q>" with…` (Google, DuckDuckGo fallbacks)
- **Providers:** apps from `shell.appLibrary`, the whole Omarchy menu (about 400 items, with breadcrumbs, guards, ✓ state and font/power-profile provider rows), and the built-ins "Omarchy Menu" and "Search Files".
- **Opening an open app [D]:** ↵ on an app focuses its most recently used window, switching to its workspace, and launches only when none is open. Windows match by desktop id, `StartupWMClass`, or the URL Chromium/Brave web app classes are built from (`RootSearch.findAppWindow`). The focus waits for the `oma-cast` layer to unmap, since Hyprland refuses focus while it holds the keyboard. Focus doesn't raise on Omarchy 4.5's floating workspaces, so the window is then brought to the top, and one minimized to the dock is moved back first, the way the dock does it. Shift+↵ ("Open New Window") always launches.
- **File search** [D] (`core/FileSearch.js`, `services/FileSearchSource.qml`): `fd` walks `$HOME` live per query (~30 ms, honours .gitignore, skips hidden paths, node_modules, __pycache__), debounced 60 ms. The last term matches basenames; earlier terms filter the path. Own scorer, not Ranker.js. Root shows the top 5 under "Files"; "Search Files" pushes a view with up to 60. Actions: open (xdg-open), Show in Files (FileManager1.ShowItems), Open in Terminal (xdg-terminal-exec), Copy Path. File rows drag out to other apps as text/uri-list (Qt Drag.Automatic); while dragging, the card hides and an empty input mask lets the drop reach the window underneath, and keyboard focus drops from Exclusive to None (Hyprland pins pointer focus to an exclusive-keyboard layer, so drops never reached other windows). A drop closes the launcher, a cancel brings it back; drag state resets on every open/close. Verified dropping into foot. No favourites/aliases/frecency on file rows. Needs Omarchy's `fd`.
- **Ranking state:** frecency (+100 per launch, 10-day half-life) and learned search terms in `db/frecency.json`. Aliases (exact → top; duplicates rejected), favourites (Ctrl+Shift+F, reorder Ctrl+Alt+↑↓) and disabled commands live in `db/settings.json` `commands`.
- **Navigation:** pushed Omarchy submenus (search within them), the alias editor, back with Esc / Ctrl+[ / Backspace on an empty query / the header arrow, and Shift+Esc to pop to root.
- **Keyboard:** Ctrl+K action panel (filterable, per-row shortcuts), ↵ / Ctrl+↵ / Ctrl+Shift+↵ for the first three actions, Ctrl+1–9, Ctrl+↑↓ to jump sections, PageUp/PageDown, ↑ on an empty root for search history, Ctrl+Shift+C copy, Alt+Shift+D disable, Ctrl + / − / 0 zoom. Numpad digits, operators and decimal separators work in queries, aliases and action filters; keypad Enter and Ctrl shortcuts retain their actions.
  - Navigation bindings (`general.navigationBindings`): `emacs` moves down with Ctrl+N; `vim-motions` moves with Ctrl+J/K and puts the action panel on **Alt+K**. Set it with `oma-cast call settings.updateGeneralSettings '{"navigationBindings":"vim-motions"}'`.
  - **Ctrl+P** opens the root dropdown (All / Applications / Commands); emacs Ctrl+P = up only works inside popups.
  - **Ctrl+T** opens the toast's actions (Copy Error Message on failures, Undo after Disable Command). **Ctrl+Shift+K** opens the About panel for the selected row.
  - **Argument pills:** "Search Google" / "Search DuckDuckGo" take a query in a pill after the search text (Tab in, Shift+Tab out).
  - **Alerts:** Shut Down, Restart, Log Out, Delete All Entries and Delete Quicklink ask first (↵ confirms, Esc cancels). `oma-cast run` skips the alert.
- **Feedback:** toasts in the footer, a HUD through Omarchy's OSD when the window closes, and a 2 px loading bar while guards and providers refresh (on every open, about 250 ms in the background).
- **Window behaviour:**
  - The `escapeKeyBehavior` setting works both ways.
  - Pop-to-root runs after `popToRootTimeout`.
  - Compact mode shows only the header until you type.
  - A launch from root clears the query [I].
  - A row is selected on hover only after a real pointer move (Omarchy's PointerMoveGate).
  - No compositor fade, like Omarchy's own overlays. The plugin adds a Hyprland layer rule for the `oma-cast` namespace (`hyprctl eval`) on load and after each `configreloaded`. Without it the launcher fades out for about 150 ms after hiding, and a screenshot launched from it captures the fading launcher.
  - Card size is configurable: the `windowWidth`/`windowHeight` general settings (default 750×475 px at uiZoom 1, ranges 500–3000 × 300–2000) set it, for example `oma-cast call settings.updateGeneralSettings '{"windowWidth":1000,"windowHeight":650}'`. Unlike `uiZoom`, they don't scale the text. Settings added after migration v1 are filled in on read by `Schema.withGeneralDefaults`, so they need no migration [D]. Settings → General has them too.
- **Calculator** (`core/Calculator.js`, our own engine [D]; no `qalc`/fend dependency): a "Calculator" section above Results with Raycast's two-pane card (question → answer, captions below each). It handles:
  - arithmetic and functions
  - Soulver-style percentages (`$30 + 20%`, `20% off 50`, `50 as a % of 200`)
  - ~250 units (`5 ft to cm`, `60 mph * 2 h`, `16px to rem`)
  - currencies (ECB rates from frankfurter.dev, cached daily in `~/.cache/oma-cast/currencies.json`; turn off with `"currencyRates": false` in config.json)
  - dates (`3 days from now`, `days until christmas`)
  - time zones (`time in tokyo`, `3pm london to nyc`; offsets come from one bash `printf %(%z)T` pass because QML has no Intl)
  - bases (`255 to hex`)
  - mixed units (`5 ft 3 in to cm`, `1 h 30 min + 45 min`)
  - work time (`40 hours in work days`, a work week is 5 days)
  - Unix time (`unix 1700000000`, `1700000000 to date`, `now to unix`, `unix time`)

  config.json sets `remToPxRate` (16), `workHoursPerDay` (8) and `clockFormat` (`auto` follows the Qt locale, or `12h` / `24h`).

  ↵ copies the answer (HUD), Ctrl+↵ pastes it through `omarchy-clipboard-paste-text`, Ctrl+Shift+C copies "question = answer". Each one saves to **Calculator History** (`db/calculator.json`, 4096 rows / 90 days): a built-in command and pushed view, searchable, Ctrl+D deletes an entry, Ctrl+Shift+D deletes all. RPC: `calculator.calculate|historyGetAll|historyDelete|historyDeleteAll|refreshCurrencies|getCurrencies`. A bare number or word (`42`, `firefox`, `kg`) never produces a row, because the section takes ↵. Fork: a lone amount and unit (`16rem`, `5 kg`, `5'10"`) converts to its counterpart (`Calculator.COUNTERPARTS`, after omalaunch; not stone, since `1st` is an ordinal); `5ft10`/`5′10″` are heights; `to feet and inches` is a target; lowercase `kwh`/`kw`/`w`/`pa`/`ghz`/`k` (kelvin) parse; lowercase `kb`/`mb`/`gb` are bytes; `oz` to a volume is fluid ounces; in/cm/mm ↔ px is CSS's 96 px per inch; `1e6` shows its value.
- **Quicklinks** (SPEC §8.4): Create / Search / Import / Export Quicklinks, Create Quicklink or Open in Browser for a typed web address, arguments in the same pills as the web searches (Tab into them, ↑/↓ steps an option, ↵ opens), Create Quicklink filled from a URL or path on the clipboard, Open With from installed apps, and Edit (Ctrl+E), Copy Link (Ctrl+Shift+C) and Delete (Ctrl+D, the Linux key in SPEC §10.3, confirmed through the alert) actions. Placeholders follow SPEC §8.3 except clipboard history, snippets and the calculator.
- **Latency:** show → mapped in 59–66 ms, hide in 24–42 ms on Omarchy 4.0.6 (`tests/smoke.sh`; it was 37–44 ms on the old `OverlayWindow`).
- **Search cost:** about 11–16 ms per keystroke inside Quickshell's V4 for 438 candidates (was 27–30 ms). `Ranker.normalize`/`transliterate` are memoized per string, which leaves the ranking identical. Measure with `node --jitless tests/bench-rootsearch.js`; V4 runs about 3× slower than that. V4 has no `Intl`, so `collate` keeps `localeCompare` there.
- **Tests:** root search, calculator and default-agent hand-off and launcher typing/keypad shortcut coverage (`node --test tests/*.test.js`).

**Default-agent hand-off (fork, 2026-10-20):** user-authorized addition outside the original phase plan. The root fallback "Ask default agent" and Ctrl+Alt+Enter pass the query to `omarchy-agent --prompt` as a literal argv element. `AgentLauncher.qml` checks the configured agent/terminal with a bounded, question-free preflight, prevents overlapping submissions and cancels on hide/unload. `Launcher.qml` dismisses the overlay before launching through `Util.execArgv`. Errors leave the query visible. There are no new dependencies, model APIs, credentials or question-history writes. Existing CLI approval behaviour is inherited. Portable checks do not establish live terminal focus, authentication, or provider compatibility; verify those on Omarchy.

**omalaunch features (fork, 2026-10-26):** emoji picker, clipboard history and window layouts, ported from cpreston321/omalaunch. They are outside the phase plan.
- **Emoji** (`core/Emoji.js`, `services/EmojiSource.qml`, the `emoji` view): Omarchy's `shell/plugins/emojis/emojis.json` plus currency signs. Groups come from CLDR boundaries (`Emoji.GROUPS`), and an out-of-order dataset falls back to an ungrouped grid. Frequently Used lives in `db/emoji.json`. Paste goes through `omarchy-menu-emoji-insert`. RPC `emoji.grid`.
- **Clipboard History** (`core/Clipboard.js`, `services/ClipboardSource.qml`, the `clipboard-history` view): read-only over `~/.local/state/omarchy/clipboard-history.json`, the same path Omarchy's helpers read. Paste/copy/open pass a history index (or path, for images) to `omarchy-clipboard-paste-text|paste-file|open`, so content never appears in argv. The detail pane is `ui/DetailPane.qml` via `rootSearch.getDetail`.
- **Script menus** (`core/ScriptMenu.js`, `services/ScriptRunner.qml`, the `script-menu` / `script-input` views): a port of omalaunch's menu protocol. A script prints `{items}` with argv commands, `input` prompts (`{input}` is one argv element), `confirm`, `submenu`, `document` previews and Ctrl+K `actions`. `closeOnDispatch` closes at once, `closeOnSuccess` waits for exit 0, and otherwise oma-cast waits, toasts the last line of output and reloads every menu. Sources are listed in `ScriptMenu.SOURCES`. The only one is `plugin/extensions/layouts/layouts` (Python, from omalaunch, with a `document` added to each layout row), and its top-level rows are root-search candidates while typing.
- A second script source, `plugin/extensions/user-actions/actions`, turns omalaunch's `extensions.d` "action" definitions into root-search rows (`closeOnDispatch`, prefixes as `keywords`).
- **Bar button** (`bar-button/`, plugin `typecraft.oma-cast-button`, `oma-cast install-button`): a separate bar-widget plugin copied in as real files. Qt fails `Qt.createComponent` on a bar widget reached through the symlinked plugin folder with "File name case mismatch" (Loader-loaded menus are unaffected), so it can't live in `plugin/`.
- Qt's JS `Array.sort` is not stable, so never rely on sort order for ties. Action order decides what ↵ runs.

**Quicklinks, snippets and Settings (fork, 2026-10-26):**
- Quicklinks are upstream PR #8, merged into the fork. Its `editor` flag (views whose header text is a value being edited) also covers the fork's `script-input` prompt.
- **Snippets** (`core/Snippets.js`, `db/snippets.json`, the `snippets` view): Phase 4 without the expansion engine (launcher only, as decided with the user). The placeholder lexer and date formatting are Quicklinks.js's, passed in as `deps.lexer` (core modules don't import each other). Snippet rules: `{cursor}` at most once, `{snippet}` nests one level (the nested one may not use `{snippet}`/`{argument}`), `{calculator}` uses the built-in engine, `{clipboard offset=N}` reads clipboard history, `{selection}` is refused, and an unknown `{word}` is literal. `services/TextPaster.qml` pipes the text to wl-copy on stdin (never argv), presses Shift+Insert, then Left × the characters after `{cursor}`.
- **Settings window** (`ui/settings/`, a Quickshell `FloatingWindow` built from Omarchy's `qs.Ui` controls): General, Commands, Snippets, Quicklinks, Calculator. `settings.updateConfig` writes config.json, validating each key with `Schema.validConfigValue` and keeping keys it doesn't know; the write is asynchronous. Opened by `builtin:settings`, Ctrl+, the `settings` IPC function and `oma-cast settings [tab]`; any action can return `backend.openSettings({tab, snippetId|quicklinkId})`.

**More settings (fork, 2026-10-26):**
- New general settings live in `Schema.generalAdditions` (#11's additive defaults, filled in on read; lists validated by `generalLists`). `Backend.general` is the merged view.
- **Hotkeys** (`core/Hotkeys.js`): Hyprland notation, `fromQt` for the recorder, `conflicts` against Search Keybindings rows, `luaFile` for `~/.config/hypr/oma-cast.lua`. Each command hotkey stores `hotkeyTitle`, so the file depends only on settings; it is rewritten (then `hyprctl reload`) only after a hotkey changes or on `hotkeys.write`, never at startup. Recording enters the `oma-cast-record` submap, which the file defines (`hl.define_submap` needs at least one bind). `oma-cast setup hyprland` asks the running plugin to write the file.
- `windowPresentationMode`: focused monitor from `Hyprland.focusedMonitor` before showing; "mouse-screen" corrects it with `hyprctl cursorpos` (only with more than one screen).
- Primary actions: `RootSearch.actionsFor(candidate, prefs)` orders each paste/copy pair; `"open"` (click, `oma-cast run`, hotkeys) maps to the preference in the backend.
- Fallbacks: `general.fallbacks` (built-in ids or `quicklink:<id>`); a quicklink fallback row is `fallback-quicklink:<id>` and gets the query as its first argument.
- Data: `data.backup` writes one JSON document (settings, commands, snippets, quicklinks, emoji usage) through the export process; `data.restore` replaces settings and imports the rest.
- `tests/qml-lint.test.js` catches a function named `<property>Changed`, which stops a QML file loading (it took the plugin down once).

Stubbed / not yet:
- Snippet keyword expansion in other apps (SPEC §5.4) needs evdev/uinput access; not built.
- No deep links (`oma-cast://`); Phase 2 or 9.

Won't do (decided 2026-10-22):
- Keystroke buffering. Keys sent within ~40 ms of the hotkey go to the window underneath; fixing it needs a parked surface, which Omarchy avoids (SPEC §12 Phase 1).
- Calculator: Color, Weather and Flight results, crypto, pinned history entries and a history detail pane. Trig takes radians unless given `°`/`deg` [D].

Deviations from the original spec (SPEC §2.0 and the Phase 1 note in §12):
- A Quickshell plugin instead of Tauri + Node; there's no NDJSON supervisor until Phase 5.
- JSON documents instead of SQLite; no DB encryption or libsecret key.
- Logs go to the shell log; `config.json` instead of `config.toml`; no D-Bus name.
- The Omarchy theme replaces Raycast's 8 themes; the HUD is Omarchy's OSD.

Testing lesson: the query survives hide/show until pop-to-root. A live test must clear it first (Ctrl+U), or typed text gets appended to the old query. Pressing ↵ on a stale query once opened real browser tabs.
