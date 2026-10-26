import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "core/Rpc.js" as Rpc
import "core/Paths.js" as Paths
import "core/Log.js" as Log
import "core/Schema.js" as Schema
import "core/Ranker.js" as Ranker
import "core/Frecency.js" as Frecency
import "core/OmarchyMenu.js" as OmarchyMenu
import "core/RootSearch.js" as RootSearch
import "core/Quicklinks.js" as Quicklinks
import "core/Snippets.js" as Snippets
import "core/Hotkeys.js" as Hotkeys
import "core/Agent.js" as Agent
import "core/Calculator.js" as Calculator
import "core/Emoji.js" as Emoji
import "core/Clipboard.js" as Clipboard
import "core/ScriptMenu.js" as ScriptMenu
import "core/Keybindings.js" as Keybindings
import "core/FileSearch.js" as FileSearch
import "services"

Item {
  id: backend

  readonly property string version: "0.1.0"
  readonly property var paths: Paths.resolve(function(name) { return Quickshell.env(name) })
  readonly property string desktop: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? "hyprland" : "unknown"

  property var appLibrary: null
  property var summon: null

  property var config: Schema.withConfigDefaults(null)
  property bool directoriesReady: false
  readonly property bool ready: directoriesReady && settingsStore.loaded && frecencyStore.loaded && calculatorStore.loaded

  readonly property var registry: Rpc.createRegistry()
  readonly property double startedAt: Date.now()
  readonly property var deps: ({ Ranker: Ranker, Frecency: Frecency, OmarchyMenu: OmarchyMenu, Quicklinks: Quicklinks })

  property var candidates: []
  property var candidatesById: ({})
  property int candidatesRevision: 0
  readonly property bool loading: menuSource.loading || agentLauncher.checking || scriptRunner.running
    || (keybindingsSource.loading && !keybindingsSource.rows.length) || fileSource.loading
  // plugin/ on disk, for the scripts bundled with it (ScriptMenu.SOURCES).
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""))
  // Bumped when a pushed view's data changes (clipboard, emoji usage, script
  // menus), and when a detail pane's content arrives.
  property int viewRevision: 0
  property int detailRevision: 0
  // Bumped when exchange rates or zone offsets arrive, so an open
  // calculator row re-evaluates.
  readonly property int calculatorRevision: (calculatorData.rates ? 1 : 0) + calculatorData.ratesFetchedAt + calculatorData.zonesAt

  signal notification(string method, var data)

  // Newer Omarchy shells provide Translations. Keep it optional so the
  // feature also loads on 4.0.5, using the bundled English catalog there.
  property var keybindingStrings: null
  readonly property var keybindingEnglish: {
    try { return JSON.parse(keybindingCatalog.text()) } catch (e) { return ({}) }
  }

  FileView {
    id: keybindingCatalog
    path: Qt.resolvedUrl("i18n/en.json")
    blockLoading: true
    printErrors: false
  }

  function keybindingText(key) {
    var id = "keybindings." + key
    return backend.keybindingStrings ? backend.keybindingStrings.t(id) : (backend.keybindingEnglish[id] || id)
  }

  // ------------------------------------------------------------- dispatch

  function call(method, data) { return Rpc.call(backend.registry, method, data) }
  function callSync(method, data) { return Rpc.callSync(backend.registry, method, data) }
  function subscribe(method, callback) { return Rpc.subscribe(backend.registry, method, callback) }

  function emit(method, data) {
    Rpc.emit(backend.registry, method, data, function(m, error) {
      backend.log("error", "rpc", "subscriber of " + m + " threw: " + error)
    })
    backend.notification(method, data)
  }

  function log(level, category, message, metadata) {
    if (!Log.shouldLog(level, backend.config.logLevel)) return
    var line = Log.format(level, category, message, metadata)
    var i = Log.levelIndex(level)
    if (i >= Log.levelIndex("error")) console.error(line)
    else if (i >= Log.levelIndex("warning")) console.warn(line)
    else if (i >= Log.levelIndex("info")) console.info(line)
    else console.log(line)
  }


  function appEntries() {
    if (backend.appLibrary) return backend.appLibrary.sortedEntries("").map(function(row) { return row.entry })
    return (DesktopEntries.applications.values || []).filter(function(e) { return !e.noDisplay })
  }

  function rebuildCandidates() {
    var next = []
    var apps = backend.appEntries()
    for (var i = 0; i < apps.length; i++) if (apps[i] && apps[i].id) next.push(RootSearch.appCandidate(apps[i]))
    next = next.concat(RootSearch.menuCandidates(menuSource.tree, menuSource.guards, menuSource.providerItems, backend.deps))
    for (var b = 0; b < RootSearch.BUILTINS.length; b++) {
      var builtin = RootSearch.builtinCandidate(RootSearch.BUILTINS[b])
      if (builtin.id === "builtin:keybindings") {
        builtin.title = backend.keybindingText("title")
        builtin.subtitle = backend.keybindingText("subtitle")
      }
      next.push(builtin)
    }
    if (backend.general.rootKeybindings) next = next.concat(keybindingsSource.rows)
    next = next.concat(backend.scriptCandidates())
    if (quicklinksStore.loaded) next = next.concat(Quicklinks.list(quicklinksStore.doc).map(Quicklinks.toCandidate))
    if (snippetsStore.loaded) next = next.concat(Snippets.list(snippetsStore.doc).map(function(item) { return Snippets.toCandidate(item, snippetsStore.doc, backend.snippetDeps) }))
    var byId = ({})
    for (var j = 0; j < next.length; j++) byId[next[j].id] = next[j]
    backend.candidates = next
    backend.candidatesById = byId
    backend.candidatesRevision++
  }

  Timer {
    id: rebuildTimer
    interval: 30
    onTriggered: backend.rebuildCandidates()
  }

  // General settings with every fork default filled in (Schema.withGeneralDefaults).
  readonly property var general: {
    backend.storeRevision
    return Schema.withGeneralDefaults(settingsStore.loaded ? settingsStore.doc.general : null)
  }

  // {quicklink id: name}, for quicklink fallbacks.
  function quicklinkNames() {
    var out = ({})
    var list = quicklinksStore.loaded ? Quicklinks.list(quicklinksStore.doc) : []
    for (var i = 0; i < list.length; i++) out[list[i].id] = list[i].name
    return out
  }

  function searchContext() {
    var g = backend.general
    return {
      commands: settingsStore.loaded ? settingsStore.doc.commands : ({}),
      frecency: frecencyStore.loaded ? frecencyStore.doc.items : ({}),
      nowMs: Date.now(),
      sensitivity: g.rootSearchSensitivity || "medium",
      suggestionsLimit: g.suggestionsLimit,
      fallbacks: g.fallbacks,
      fallbackQuicklinks: backend.quicklinkNames()
    }
  }

  // What ↵ does for the paste/copy pairs (RootSearch.actionsFor).
  function primaryPrefs() {
    var g = backend.general
    return { clipboard: g.clipboardPrimary, emoji: g.emojiPrimary, snippet: g.snippetPrimary, calculator: g.calculatorPrimary }
  }

  function decorated(id) {
    var c = backend.candidatesById[id]
    return c ? RootSearch.decorate(c, backend.searchContext(), backend.deps) : null
  }

  // ------------------------------------------------------------ calculator

  // 12- or 24-hour clock from config.json clockFormat, else the Qt locale.
  readonly property bool hour12: backend.config.clockFormat === "auto"
    ? Qt.locale().timeFormat(Locale.ShortFormat).toLowerCase().indexOf("ap") >= 0
    : backend.config.clockFormat === "12h"

  function calculatorEnv() {
    return {
      nowMs: Date.now(),
      localOffset: -new Date().getTimezoneOffset(),
      hour12: backend.hour12,
      rates: backend.config.currencyRates ? calculatorData.rates : null,
      zones: calculatorData.zones,
      remToPxRate: backend.config.remToPxRate,
      workHoursPerDay: backend.config.workHoursPerDay,
      homeCurrency: backend.homeCurrency(),
      secondCurrency: backend.secondCurrency()
    }
  }

  // Where a lone amount of money converts to (config homeCurrency/secondCurrency).
  function homeCurrency() {
    var set = backend.config.homeCurrency
    return set && set !== "auto" ? set : (Calculator.localeCurrency(Qt.locale().name) || "USD")
  }
  function secondCurrency() {
    var set = backend.config.secondCurrency
    if (set && set !== "auto") return set
    return backend.homeCurrency() === "EUR" ? "USD" : "EUR"
  }

  function calculate(query) {
    try {
      return Calculator.evaluate(query, backend.calculatorEnv())
    } catch (e) {
      backend.log("error", "calculator", "evaluating failed: " + e, { query: query })
      return null
    }
  }

  function saveCalculation(entry) {
    calculatorStore.update(function(doc) {
      doc.history = Calculator.pushHistory(doc.history, {
        id: String(Date.now()), query: entry.query, result: entry.result, copy: entry.copy, kind: entry.kind
      }, Date.now())
    })
    backend.emit("calculator.historyStateChanged", null)
  }

  // An action on the inline Calculator row or a Calculator History entry.
  // entry: {query, result, copy, kind}; history: whether it is saved already.
  function calculatorAction(action, entry, historyId) {
    if (action === "open") action = backend.general.calculatorPrimary === "paste" ? "paste-answer" : "copy-answer"
    switch (action) {
      case "copy-answer":
        if (!historyId) backend.saveCalculation(entry)
        Util.execArgv(["wl-copy", "--", entry.copy])
        return { close: true, hud: "Copied to Clipboard" }
      case "paste-answer":
        if (!historyId) backend.saveCalculation(entry)
        // Omarchy's own paste: copies, waits for our window to unmap, types.
        Util.execArgv(["omarchy-clipboard-paste-text", entry.copy])
        return { close: true }
      case "copy-question-answer":
        if (!historyId) backend.saveCalculation(entry)
        Util.execArgv(["wl-copy", "--", entry.query + " = " + entry.result])
        return { close: true, hud: "Copied to Clipboard" }
      case "open-history":
        return { push: { kind: "calculator-history", title: "Calculator History" } }
      case "delete-entry":
        calculatorStore.update(function(doc) { doc.history = doc.history.filter(function(h) { return h.id !== historyId }) })
        backend.emit("calculator.historyStateChanged", null)
        return { toast: { style: "success", title: "Entry deleted" } }
      case "delete-all-entries":
        calculatorStore.update(function(doc) { doc.history = [] })
        backend.emit("calculator.historyStateChanged", null)
        return { toast: { style: "success", title: "History cleared" } }
    }
    throw new Error("Unknown action " + action)
  }

  function historyEntry(id) {
    var key = String(id).slice("calculator-history:".length)
    var list = calculatorStore.loaded ? calculatorStore.doc.history : []
    for (var i = 0; i < list.length; i++) if (list[i].id === key) return list[i]
    return null
  }

  // ------------------------------------------------- emoji and clipboard

  function emojiAction(action, emoji) {
    if (action === "open") action = backend.general.emojiPrimary
    if (action === "paste") {
      emojiStore.update(function(doc) { doc.usage = Emoji.recordUsage(doc.usage, emoji, Date.now()) })
      // Omarchy's own insert: copies, waits for our window to unmap, types.
      Util.execArgv(["omarchy-menu-emoji-insert", emoji])
      return { close: true }
    }
    if (action === "copy") {
      emojiStore.update(function(doc) { doc.usage = Emoji.recordUsage(doc.usage, emoji, Date.now()) })
      Util.execArgv(["wl-copy", "--", emoji])
      return { close: true, hud: "Copied " + emoji }
    }
    throw new Error("Unknown action " + action)
  }

  function clipboardEntry(id) {
    var entry = clipboardSource.entry(Number(String(id).slice("clipboard:".length)))
    if (!entry) throw new Error("That entry is no longer in the clipboard history")
    return entry
  }

  function clipboardAction(action, entry) {
    if (action === "open") action = backend.general.clipboardPrimary
    switch (action) {
      case "paste":
        Util.execArgv(Clipboard.pasteArgv(entry, false))
        return { close: true }
      case "copy":
        Util.execArgv(Clipboard.pasteArgv(entry, true))
        return { close: true, hud: "Copied to Clipboard" }
      case "open-entry":
        Util.execArgv(Clipboard.openArgv(entry))
        return { close: true }
    }
    throw new Error("Unknown action " + action)
  }

  // ---------------------------------------------------------- script menus

  // menuKey -> {command, title, items, error, loading}. A source's own menu is
  // keyed by the source id; submenus by ScriptMenu.menuKey(command).
  property var scriptMenus: ({})
  // JSON(command) -> {doc, error, loading} for detail panes.
  property var scriptDocuments: ({})

  function scriptMenuFor(view) {
    var key = String(view && view.menuKey || "")
    if (backend.scriptMenus[key]) return backend.scriptMenus[key]
    var source = ScriptMenu.sourceById(key)
    var command = source ? ScriptMenu.sourceCommand(source, backend.pluginDir) : (view && view.command)
    if (!command) throw new Error("Unknown menu " + key)
    var menu = { command: command, title: String(view.title || (source && source.title) || ""), items: [], error: "", loading: false, loaded: false }
    backend.scriptMenus[key] = menu
    backend.loadScriptMenu(key)
    return menu
  }

  function loadScriptMenu(key) {
    var menu = backend.scriptMenus[key]
    if (!menu || menu.loading) return
    menu.loading = true
    scriptRunner.run(menu.command, function(ok, out, err) {
      menu.loading = false
      menu.loaded = true
      if (ok) {
        var parsed = ScriptMenu.parse(out)
        menu.items = parsed.items
        menu.error = parsed.error
      } else {
        menu.error = ScriptMenu.summary(err) || "The menu script failed"
      }
      if (menu.error) backend.log("warning", "script-menu", key + ": " + menu.error)
      if (ScriptMenu.sourceById(key)) rebuildTimer.restart()
      backend.viewRevision++
    })
  }

  // Everything a script may have changed is reloaded after it runs.
  function refreshScriptMenus() {
    backend.scriptDocuments = ({})
    for (var key in backend.scriptMenus) backend.loadScriptMenu(key)
    for (var i = 0; i < ScriptMenu.SOURCES.length; i++) {
      var source = ScriptMenu.SOURCES[i]
      if (source.globalSearch) backend.scriptMenuFor({ menuKey: source.id })
    }
    backend.detailRevision++
  }

  // Top-level items of globalSearch sources, found by root search while typing.
  function scriptCandidates() {
    var out = []
    for (var i = 0; i < ScriptMenu.SOURCES.length; i++) {
      var source = ScriptMenu.SOURCES[i]
      var menu = backend.scriptMenus[source.id]
      if (!source.globalSearch || !menu) continue
      for (var j = 0; j < menu.items.length; j++)
        out.push(ScriptMenu.candidate(source.id, menu.items[j], source.title, source.typeLabel, "searching"))
    }
    return out
  }

  function scriptItem(rowId) {
    var ref = ScriptMenu.splitRowId(rowId)
    var menu = ref && backend.scriptMenus[ref.menuKey]
    var item = menu ? menu.items.filter(function(i) { return i.id === ref.itemId })[0] : null
    if (!item) throw new Error("That item is no longer available")
    return { menuKey: ref.menuKey, item: item }
  }

  function runScriptPlan(plan, label) {
    if (plan.error) throw new Error(plan.error)
    if (plan.mode === "dispatch") {
      Util.execArgv(plan.run)
      return { close: true }
    }
    scriptRunner.run(plan.run, function(ok, out, err) {
      var message = ok ? (ScriptMenu.summary(out) || label) : (ScriptMenu.summary(err) || ScriptMenu.summary(out) || label + " failed")
      backend.emit("script.finished", { ok: ok, close: ok && plan.mode === "close-on-success", message: message })
      backend.refreshScriptMenus()
    })
    return { pending: true }
  }

  function scriptAction(data) {
    var found = backend.scriptItem(data.id)
    var action = String(data.action || "open")
    var target = ScriptMenu.targetFor(found.item, action)
    // Favourites, aliases and Disable on root-search rows.
    if (!target) return backend.performAction(data)
    var plan = ScriptMenu.plan(found.menuKey, found.item, target, action, !!data.confirmed)
    if (plan.confirm) return { confirm: plan.confirm }
    if (plan.push) return { push: plan.push }
    if (plan.detail) return {}
    if (backend.candidatesById[data.id]) backend.recordVisit(data.id, String(data.query || "").trim())
    return backend.runScriptPlan(plan, target.label)
  }

  function scriptActions(rowId) {
    var found = backend.scriptItem(rowId)
    var list = ScriptMenu.actionsFor(found.item)
    var candidate = backend.decorated(rowId)
    if (candidate) {
      var extras = RootSearch.actionsFor(candidate).filter(function(a) { return a.section === "favorites" || a.section === "configure" || a.id === "disable" })
      list = list.concat(extras)
    }
    return list
  }

  function scriptDetail(rowId) {
    var item = backend.scriptItem(rowId).item
    var fallback = { title: item.label, subtitle: item.description, status: "", blocks: [], metadata: [] }
    if (!item.document) return fallback
    var key = JSON.stringify(item.document.command)
    var cached = backend.scriptDocuments[key]
    if (cached) return cached.doc ? cached.doc : Object.assign({}, fallback, { loading: cached.loading, status: cached.error })
    var entry = { doc: null, error: "", loading: true }
    backend.scriptDocuments[key] = entry
    // Called from the detail pane's binding: starting the process there would
    // bind the pane to the runner's busy count it changes (a binding loop).
    var command = item.document.command
    Qt.callLater(function() {
      scriptRunner.run(command, function(ok, out, err) {
        entry.loading = false
        entry.doc = ok ? ScriptMenu.parseDocument(out) : null
        if (!entry.doc) entry.error = ScriptMenu.summary(err) || "No preview"
        backend.detailRevision++
      })
    })
    return Object.assign({}, fallback, { loading: true })
  }

  // --------------------------------------------------------------- hotkeys

  readonly property string hyprDir: (Quickshell.env("XDG_CONFIG_HOME") || (backend.paths.home + "/.config")) + "/hypr"
  readonly property string hotkeysPath: backend.hyprDir + "/oma-cast.lua"
  // Whether hyprland.lua loads oma-cast.lua; without it hotkeys do nothing.
  property bool hotkeysLoaded: false
  property bool hotkeysDirty: false

  // The normalized hotkey, or throws: invalid, or already another command's.
  // owner: "launcher" or a command id.
  function checkHotkey(value, owner) {
    var text = String(value || "").trim()
    if (!text) return ""
    var problem = Hotkeys.validate(text)
    if (problem) throw new Error(problem)
    var key = Hotkeys.normalize(text)
    if (owner !== "launcher" && Hotkeys.normalize(backend.general.launcherHotkey) === key) throw new Error(Hotkeys.display(key) + " already opens oma-cast")
    var commands = settingsStore.doc.commands
    for (var id in commands) {
      if (id !== owner && commands[id].hotkey && Hotkeys.normalize(commands[id].hotkey) === key)
        throw new Error(Hotkeys.display(key) + " is already used by " + (commands[id].hotkeyTitle || id))
    }
    return key
  }

  // Every hotkey oma-cast binds: [{hotkey, id, title}], the launcher's first.
  function hotkeyEntries() {
    var out = []
    var commands = settingsStore.loaded ? settingsStore.doc.commands : ({})
    for (var id in commands) if (commands[id].hotkey) out.push({ hotkey: commands[id].hotkey, id: id, title: commands[id].hotkeyTitle || id })
    out.sort(function(a, b) { return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : 1 })
    return out
  }

  function hotkeyStatus() {
    var entries = backend.hotkeyEntries()
    return {
      path: backend.hotkeysPath,
      loaded: backend.hotkeysLoaded,
      launcher: backend.general.launcherHotkey,
      commands: entries
    }
  }

  // Omarchy bindings already on `hotkey` (from Search Keybindings), not
  // counting oma-cast's own.
  function hotkeyConflicts(hotkey) {
    var ours = backend.hotkeyEntries().map(function(e) { return e.hotkey }).concat([backend.general.launcherHotkey])
    return Hotkeys.conflicts(hotkey, keybindingsSource.rows, ours)
  }

  function scheduleHotkeys() {
    backend.hotkeysDirty = true
    hotkeysTimer.restart()
  }

  // Rewrites oma-cast.lua when it changed, then reloads Hyprland.
  function writeHotkeys(force) {
    var text = Hotkeys.luaFile(backend.general.launcherHotkey, backend.hotkeyEntries())
    backend.hotkeysDirty = false
    if (!force && hotkeysFile.loaded && hotkeysFile.text() === text) return false
    hotkeysFile.setText(text)
    reloadTimer.restart()
    return true
  }

  Timer { id: hotkeysTimer; interval: 300; onTriggered: if (backend.hotkeysDirty) backend.writeHotkeys(false) }
  // After the atomic write lands.
  Timer { id: reloadTimer; interval: 250; onTriggered: Quickshell.execDetached(["hyprctl", "reload"]) }

  function afterGeneralUpdate(patch) {
    if (patch.launcherHotkey !== undefined) backend.scheduleHotkeys()
    if (patch.rootKeybindings !== undefined) rebuildTimer.restart()
    if (patch.fileFolders !== undefined || patch.fileHidden !== undefined || patch.fileExcludes !== undefined) fileSource.reset()
  }

  FileView {
    id: hotkeysFile
    property bool loaded: false
    path: backend.hotkeysPath
    atomicWrites: true
    printErrors: false
    onLoaded: hotkeysFile.loaded = true
    onLoadFailed: hotkeysFile.loaded = false
  }

  FileView {
    path: backend.hyprDir + "/hyprland.lua"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: backend.hotkeysLoaded = /^\s*require\(\s*["']hypr\.oma-cast["']\s*\)/m.test(text())
    onLoadFailed: backend.hotkeysLoaded = false
  }

  // ------------------------------------------------------------------ data

  // Applies what it can of a general-settings patch, skipping invalid keys.
  function applyGeneralLoosely(patch) {
    var current = backend.general
    var good = ({}), skipped = 0
    for (var key in patch) {
      var v = patch[key]
      var choices = Schema.generalChoices[key]
      var ok = current[key] !== undefined && typeof v === typeof current[key] && Array.isArray(v) === Array.isArray(current[key])
        && !(choices && choices.indexOf(v) < 0) && !Schema.checkGeneralValue(key, v)
      if (key === "launcherHotkey" && ok && v && Hotkeys.validate(v)) ok = false
      if (ok) good[key] = key === "launcherHotkey" ? Hotkeys.normalize(v) || "" : v
      else skipped++
    }
    settingsStore.update(function(doc) { for (var k in good) doc.general[k] = good[k] })
    backend.afterGeneralUpdate(good)
    return skipped
  }

  // Everything you set up, in one JSON document (Settings → Data).
  function backupDocument() {
    return {
      app: "oma-cast", backupVersion: 1, createdAt: new Date().toISOString(),
      general: settingsStore.doc.general,
      commands: settingsStore.doc.commands,
      snippets: Snippets.exportList(snippetsStore.doc),
      quicklinks: Quicklinks.exportList(quicklinksStore.doc),
      emojiUsage: emojiStore.loaded ? emojiStore.doc.usage : ({})
    }
  }

  // Settings and command settings are replaced; snippets and quicklinks are
  // imported beside the current ones (duplicates skipped); emoji counts merge.
  function restoreBackup(text) {
    var doc
    try { doc = JSON.parse(String(text || "")) } catch (e) { throw new Error("That is not valid JSON") }
    if (!doc || doc.app !== "oma-cast" || doc.backupVersion !== 1) throw new Error("That is not an oma-cast backup")
    var parts = []
    var skipped = doc.general && typeof doc.general === "object" ? backend.applyGeneralLoosely(doc.general) : 0
    if (doc.commands && typeof doc.commands === "object" && !Array.isArray(doc.commands)) {
      var commands = ({})
      for (var id in doc.commands) {
        var c = doc.commands[id], clean = ({})
        if (!c || typeof c !== "object") continue
        if (typeof c.alias === "string" && c.alias && !/\s/.test(c.alias)) clean.alias = c.alias.toLowerCase()
        if (c.enabled === false) clean.enabled = false
        if (typeof c.favoriteOrder === "number") clean.favoriteOrder = c.favoriteOrder
        if (typeof c.hotkey === "string" && !Hotkeys.validate(c.hotkey)) { clean.hotkey = Hotkeys.normalize(c.hotkey); clean.hotkeyTitle = String(c.hotkeyTitle || id) }
        if (Object.keys(clean).length) commands[id] = clean
      }
      settingsStore.update(function(d) { d.commands = commands })
      parts.push(Object.keys(commands).length + " command settings")
    }
    if (Array.isArray(doc.snippets) && doc.snippets.length) {
      var sn = Snippets.importText(snippetsStore.doc, JSON.stringify(doc.snippets), { now: Date.now() }, backend.snippetDeps)
      if (!sn.error && sn.added) backend.storeSnippets(sn.doc)
      parts.push((sn.added || 0) + " snippets")
    }
    if (Array.isArray(doc.quicklinks) && doc.quicklinks.length) {
      var ql = Quicklinks.importText(quicklinksStore.doc, JSON.stringify(doc.quicklinks), { apps: backend.installedApps(), now: Date.now() })
      if (!ql.error && ql.added) backend.storeQuicklinks(ql.doc)
      parts.push((ql.added || 0) + " quicklinks")
    }
    if (doc.emojiUsage && typeof doc.emojiUsage === "object") {
      emojiStore.update(function(d) {
        for (var k in doc.emojiUsage) {
          var u = doc.emojiUsage[k]
          if (!u || typeof u.count !== "number") continue
          var mine = d.usage[k]
          if (!mine || mine.count < u.count) d.usage[k] = { count: u.count, lastUsedAt: Number(u.lastUsedAt) || 0 }
        }
      })
    }
    backend.scheduleHotkeys()
    rebuildTimer.restart()
    return { ok: true, title: "Restored " + (parts.length ? parts.join(", ") : "settings") + (skipped ? " (" + skipped + " settings skipped)" : "") }
  }

  function restoreFrom(input) {
    var path = String(input || "").trim()
    if (path === "~" || path.indexOf("~/") === 0) path = backend.paths.home + path.slice(1)
    if (path && path.charAt(0) !== "/") throw new Error("Type a full path, starting with / or ~")
    if (path) return backend.restoreBackup(backend.readTextFile(path))
    if (pasteProc.running) throw new Error("Still reading the clipboard")
    backend.paste(false, function(text) {
      var outcome
      try { outcome = backend.restoreBackup(text) }
      catch (e) { outcome = { ok: false, title: String(e.message || e) } }
      backend.emit("data.restored", outcome)
    })
    return { pending: true, ok: true, title: "Reading the clipboard…" }
  }

  // ------------------------------------------------------------- execution

  function summonPlugin(id, payload) {
    if (backend.summon && backend.summon(id, payload)) return
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", id, payload || "{}"])
  }

  function runShell(command) {
    var summon = OmarchyMenu.summonAction(command)
    if (summon) backend.summonPlugin(summon.id, summon.payload)
    else Util.execDetached(command)
  }

  function recordVisit(id, query) {
    if (!frecencyStore.loaded) return
    frecencyStore.update(function(doc) {
      doc.items[id] = Frecency.recordVisit(doc.items[id] || null, Date.now(), query || "")
      if (query) doc.searchHistory = Schema.pushSearchHistory(doc.searchHistory, query)
    })
  }

  function updateCommand(id, mutator) {
    settingsStore.update(function(doc) {
      var current = doc.commands[id] || {}
      var next = mutator(JSON.parse(JSON.stringify(current)))
      var empty = true
      for (var k in next) if (next[k] !== null && next[k] !== undefined && next[k] !== "") empty = false
      if (empty) delete doc.commands[id]
      else doc.commands[id] = next
    })
    backend.emit("settings.commandSettingsChanged", { commandId: id })
  }

  function omarchyRouteFor(candidate) {
    if (candidate.kind === "omarchy-action") {
      var item = menuSource.tree.items[candidate.menuId]
      return item && item.parent ? item.parent : "root"
    }
    return candidate.kind === "omarchy-link" ? candidate.target : candidate.menuId
  }

  function launchApp(candidate) {
    if (backend.appLibrary) backend.appLibrary.launch(candidate.appId, candidate.title)
    else Util.execArgv(["uwsm-app", "--", "gtk-launch", candidate.appId + ".desktop"])
  }

  function performAction(data) {
    var id = String(data && data.id || "")
    var action = String(data && data.action || "open")
    var query = String(data && data.query || "").trim()
    var candidate = backend.decorated(id)
    if (!candidate) throw new Error("Unknown command " + id)
    if (candidate.kind === "keybinding" && action === "open") action = "copy-shortcut"

    if (action === "open") {
      switch (candidate.kind) {
        case "app":
          backend.recordVisit(id, query)
          appFocuser.open(candidate)
          return { close: true }
        case "omarchy-action":
          if (candidate.disabled) return { toast: { style: "failure", title: candidate.title + " is already set up" } }
          backend.recordVisit(id, query)
          if (/^omarchy(?:-menu-keybindings| menu keybindings)$/.test(candidate.action.trim())) {
            keybindingsSource.refresh()
            return { push: { kind: "keybindings", title: backend.keybindingText("title") } }
          }
          backend.runShell(candidate.action)
          return { close: true }
        case "omarchy-menu":
          backend.recordVisit(id, query)
          return { push: { kind: "menu", menuId: candidate.menuId, title: candidate.title } }
        case "omarchy-link":
          backend.recordVisit(id, query)
          var target = menuSource.tree.items[candidate.target]
          if (!target) return { toast: { style: "failure", title: "Menu " + candidate.target + " not found" } }
          return { push: { kind: "menu", menuId: target.id, title: target.label } }
        case "builtin":
          if (candidate.run.url) {
            var values = (data && data.arguments) || {}
            var missing = RootSearch.missingArgument(candidate.arguments, values)
            if (missing >= 0) throw new Error("Type a " + candidate.arguments[missing].placeholder.toLowerCase() + " first")
            backend.recordVisit(id, query)
            Util.execArgv(["omarchy-launch-browser", RootSearch.fillArguments(candidate.run.url, values)])
            return { close: true }
          }
          backend.recordVisit(id, query)
          if (candidate.run.quicklinks) return backend.quicklinksCommand(candidate.run.quicklinks)
          if (candidate.run.settings) return backend.openSettings(candidate.run.settings)
          if (candidate.run.view === "keybindings") {
            keybindingsSource.refresh()
            return { push: { kind: "keybindings", title: candidate.title } }
          }
          if (candidate.run.push) return { push: candidate.run.push }
          if (candidate.run.summon) backend.summonPlugin(candidate.run.summon, candidate.run.payload || "{}")
          return { close: true }
        case "quicklink":
          return backend.openQuicklink(candidate.quicklinkId, (data && data.arguments) || {}, query)
        case "snippet":
          return backend.pasteSnippet(candidate.snippetId, (data && data.arguments) || {}, query, backend.general.snippetPrimary)
        case "fallback":
          Util.execArgv(["omarchy-launch-browser", RootSearch.fallbackUrl(candidate, query)])
          return { close: true }
      }
      throw new Error("Cannot open " + id)
    }

    switch (action) {
      case "open-new":
        backend.recordVisit(id, query)
        backend.launchApp(candidate)
        return { close: true }
      case "copy-shortcut":
        if (candidate.kind !== "keybinding") throw new Error("Not a keybinding")
        Util.execArgv(["wl-copy", "--", candidate.shortcut])
        return { toast: { style: "success", title: backend.keybindingText("copied") } }
      case "open-in-omarchy-menu":
        backend.summonPlugin("omarchy.menu", JSON.stringify({ menu: backend.omarchyRouteFor(candidate) }))
        return { close: true }
      case "edit-quicklink":
        var editing = Quicklinks.get(quicklinksStore.doc, candidate.quicklinkId)
        return { push: backend.quicklinkForm("Edit Quicklink", editing) }
      case "paste-snippet":
      case "copy-snippet":
        return backend.pasteSnippet(candidate.snippetId, (data && data.arguments) || {}, query, action === "copy-snippet" ? "copy" : "paste")
      case "edit-snippet":
        return backend.openSettings({ tab: "snippets", snippetId: candidate.snippetId })
      case "delete-snippet":
        if (!(data && data.confirmed)) return { confirm: {
          title: "Delete Snippet", destructive: true, primary: "Delete",
          message: "Delete “" + candidate.title + "”? This also removes its alias, favourite and ranking."
        } }
        var removedSnippet = backend.callSync("snippets.delete", { id: candidate.snippetId })
        if (!removedSnippet.ok) throw new Error(removedSnippet.error)
        return { toast: { style: "success", title: "Snippet deleted" } }
      case "copy-link":
        Util.execArgv(["wl-copy", "--", Quicklinks.get(quicklinksStore.doc, candidate.quicklinkId).link])
        return { close: true, hud: "Copied to Clipboard" }
      case "delete-quicklink":
        // The confirm alert, as for the other destructive actions [O].
        if (!(data && data.confirmed)) return { confirm: {
          title: "Delete Quicklink", destructive: true, primary: "Delete",
          message: "Delete “" + candidate.title + "”? This also removes its alias, favourite and ranking."
        } }
        var deleted = backend.callSync("quicklinks.delete", { id: candidate.quicklinkId })
        if (!deleted.ok) throw new Error(deleted.error)
        return { toast: { style: "success", title: "Quicklink deleted" } }
      case "copy-command":
      case "copy-id":
        Util.execArgv(["wl-copy", "--", action === "copy-id" ? candidate.appId + ".desktop" : candidate.action])
        return { close: true, hud: "Copied to Clipboard" }
      case "favorite-add":
      case "favorite-remove":
      case "favorite-up":
      case "favorite-down":
        var orders = RootSearch.reorderFavorites(settingsStore.doc.commands, id, action)
        settingsStore.update(function(doc) {
          for (var key in orders) {
            var entry = doc.commands[key] || {}
            if (orders[key] === null) delete entry.favoriteOrder
            else entry.favoriteOrder = orders[key]
            if (Object.keys(entry).length === 0) delete doc.commands[key]
            else doc.commands[key] = entry
          }
        })
        var titles = { "favorite-add": "Added to Favorites", "favorite-remove": "Removed from Favorites", "favorite-up": "Moved Up", "favorite-down": "Moved Down" }
        return { toast: { style: "success", title: titles[action] } }
      case "set-alias":
        return { push: { kind: "alias", commandId: id, title: "Alias for " + candidate.title, value: candidate.alias } }
      case "remove-alias":
        backend.updateCommand(id, function(s) { delete s.alias; return s })
        return { toast: { style: "success", title: "Alias removed" } }
      case "reset-ranking":
        frecencyStore.update(function(doc) { delete doc.items[id] })
        return { toast: { style: "success", title: "Ranking reset" } }
      case "disable":
        backend.updateCommand(id, function(s) { s.enabled = false; return s })
        // Undo on Ctrl+T: there is no settings window to re-enable it yet.
        return { toast: { style: "success", title: candidate.title + " disabled", actions: [
          { id: "undo", title: "Undo", done: candidate.title + " enabled",
            call: { method: "settings.updateCommandSettings", data: { commandId: id, enabled: true } } }
        ] } }
    }
    throw new Error("Unknown action " + action)
  }

  // -------------------------------------------------------------- snippets

  readonly property var snippetDeps: ({ lexer: Quicklinks })

  function storeSnippets(doc) {
    if (!snippetsStore.loaded) throw new Error("snippets are not loaded yet")
    if (!snippetsStore.update(function(stored) { stored.items = doc.items })) throw new Error("snippets are read-only: " + (snippetsStore.lastError || "written by a newer build"))
    rebuildTimer.restart()
  }

  // Text history entries, newest first, for {clipboard offset=N}.
  function clipboardText(offset) {
    var texts = clipboardSource.entries.filter(function(e) { return e.kind !== "image" })
    return offset < texts.length ? texts[offset].text : null
  }

  // ↵ pastes, Ctrl+↵ copies. Missing required arguments focus their pill.
  function pasteSnippet(id, values, query, mode) {
    var item = Snippets.get(snippetsStore.doc, id)
    if (!item) return { toast: { style: "failure", title: "Snippet not found" } }
    var parsed = Snippets.analyze(item.text, snippetsStore.doc, backend.snippetDeps)
    if (parsed.error) return { toast: { style: "failure", title: parsed.error } }
    var missing = parsed.arguments.some(function(a) { return !a.defaultValue && !String(values[a.name] || "").trim() })
    if (missing) return { arguments: { id: "snippet:" + item.id, title: item.name } }
    var args = Snippets.argumentValues(parsed.arguments, values)
    if (args.error) return { toast: { style: "failure", title: args.error } }
    var expanded = Snippets.expand(item.text, snippetsStore.doc, {
      now: Date.now(), values: args.values, names: backend.localeNames, uuid: Quicklinks.randomUuid,
      clipboard: backend.clipboardText,
      calculate: function(expression) { var c = backend.calculate(expression); return c ? c.copy : null }
    }, backend.snippetDeps)
    if (expanded.error) return { toast: { style: "failure", title: expanded.error } }
    backend.recordVisit("snippet:" + item.id, query)
    textPaster.run(expanded.text, mode, mode === "paste" ? expanded.cursorFromEnd : 0)
    return mode === "copy" ? { close: true, hud: "Copied to Clipboard" } : { close: true }
  }

  function snippetImportSummary(text, emptyMessage) {
    if (!String(text || "").trim()) throw new Error(emptyMessage)
    var r = Snippets.importText(snippetsStore.doc, text, { now: Date.now() }, backend.snippetDeps)
    if (r.error) throw new Error(r.error)
    if (r.added > 0) backend.storeSnippets(r.doc)
    var parts = [r.added + " imported"]
    if (r.duplicates) parts.push(r.duplicates + " already saved")
    if (r.failed.length) parts.push("skipped " + r.failed.join(", "))
    return { ok: r.added > 0 || r.failed.length === 0, title: parts.join(" · "), added: r.added }
  }

  function importSnippets(input) {
    var path = String(input || "").trim()
    if (path === "~" || path.indexOf("~/") === 0) path = backend.paths.home + path.slice(1)
    if (path && path.charAt(0) !== "/") throw new Error("Type a full path, starting with / or ~")
    if (path) return backend.snippetImportSummary(backend.readTextFile(path), path + " is empty")
    if (pasteProc.running) throw new Error("Still reading the clipboard")
    backend.paste(false, function(text) {
      var outcome
      try { outcome = backend.snippetImportSummary(text, "The clipboard is empty") }
      catch (e) { outcome = { ok: false, title: String(e.message || e) } }
      backend.emit("snippets.imported", outcome)
    })
    return { pending: true, ok: true, title: "Reading the clipboard…" }
  }

  // Merges validated keys into config.json, keeping keys this build does
  // not know (another fork's settings, or a newer build's).
  function updateConfig(patch) {
    var raw = {}
    var text = configFile.loaded ? configFile.text() : ""
    if (String(text).trim()) {
      try { raw = JSON.parse(text) } catch (e) { throw new Error("config.json is not valid JSON; fix it by hand first") }
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("config.json must hold an object")
    }
    for (var key in patch) {
      if (Schema.configDefaults[key] === undefined) throw new Error("Unknown setting " + key)
      if (!Schema.validConfigValue(key, patch[key])) throw new Error("Invalid value for " + key)
      raw[key] = patch[key]
    }
    configFile.setText(JSON.stringify(raw, null, 2) + "\n")
    backend.config = Schema.withConfigDefaults(raw)
    return backend.config
  }

  // Opens the Settings window, optionally on a tab and an item in it.
  function openSettings(target) {
    backend.emit("settings.open", target || {})
    return { close: true }
  }

  // ------------------------------------------------------------ quicklinks

  function installedApps() {
    // Every app with a desktop entry, even one hidden from search; not
    // NoDisplay handlers, which are not meant to be launched by hand.
    return Quicklinks.installedApps((DesktopEntries.applications.values || []).filter(function(e) { return !e.noDisplay }))
  }

  // Month and day names for {date}; "" is the system locale.
  function localeNames(name) {
    var locale = name ? Qt.locale(name) : Qt.locale()
    return {
      month: function(i, long) { return locale.monthName(i, long ? Locale.LongFormat : Locale.ShortFormat) },
      day: function(i, long) { return locale.dayName(i, long ? Locale.LongFormat : Locale.ShortFormat) }
    }
  }

  // The Name / Link / Open With form; `item` is null when creating.
  function quicklinkForm(title, item) {
    var value = item || {}
    return {
      kind: "quicklink-form",
      title: title,
      quicklinkId: item && item.id ? item.id : "",
      focus: 0,
      fields: [
        { key: "name", label: "Name", value: value.name || "", placeholder: "Quicklink name" },
        { key: "link", label: "Link", value: value.link || "", placeholder: "https://google.com/search?q={argument}" },
        { key: "openWith", label: "Open With", value: value.openWith || "", picker: true }
      ]
    }
  }

  function quicklinksCommand(name) {
    if (name === "create") {
      // A URL or path on the clipboard fills an untouched form when it arrives.
      if (!pasteProc.running) backend.paste(false, function(text) {
        var suggested = Quicklinks.suggestion(text)
        if (suggested) backend.emit("quicklinks.autofill", suggested)
      })
      return { push: backend.quicklinkForm("Create Quicklink", null) }
    }
    if (name === "search") return { push: { kind: "quicklinks", title: "Search Quicklinks" } }
    if (name === "import") return { push: { kind: "quicklink-import", title: "Import Quicklinks" } }
    return backend.exportQuicklinks()
  }

  function storeQuicklinks(doc) {
    // Only items: the store keeps schemaVersion and schemaHistory beside them.
    if (!quicklinksStore.update(function(stored) { stored.items = doc.items })) throw new Error("quicklinks are read-only: " + (quicklinksStore.lastError || "written by a newer build"))
    backend.rebuildCandidates()
  }

  // Arguments first (a form), then the clipboard or selection, then open.
  // values come from the launcher's argument pills, by name.
  function openQuicklink(id, values, query) {
    var item = Quicklinks.get(quicklinksStore.doc, id)
    if (!item) return { toast: { style: "failure", title: "Quicklink not found" } }
    var parsed = Quicklinks.parseLink(item.link)
    if (parsed.error) return { toast: { style: "failure", title: parsed.error } }
    var missing = parsed.arguments.some(function(a) { return !a.defaultValue && !String(values[a.name] || "").trim() })
    if (!missing) return backend.launchQuicklink(item, values, query)
    // `oma-cast run` without values: the launcher focuses the empty pill.
    return { arguments: { id: "quicklink:" + item.id, title: item.name } }
  }

  function launchQuicklink(item, values, query) {
    var parsed = Quicklinks.parseLink(item.link)
    var args = parsed.error ? parsed : Quicklinks.argumentValues(parsed, values)
    if (args.error) return { toast: { style: "failure", title: args.error } }
    var ctx = { now: Date.now(), values: args.values, clipboard: "", selection: "", uuid: Quicklinks.randomUuid(), names: backend.localeNames }
    if (!parsed.needsClipboard && !parsed.needsSelection) return backend.finishLaunch(item, ctx, query)
    if (pasteProc.running) return { toast: { style: "failure", title: "Still reading the clipboard" } }
    // Read what the link needs, then open. The launcher has closed by then,
    // so a failure becomes a notification.
    var notifyFailure = function(title, message) {
      backend.log("warning", "quicklinks", title + ": " + message)
      Quickshell.execDetached(["notify-send", "--app-name=oma-cast", title, message])
    }
    var opened = function() {
      var outcome = backend.finishLaunch(item, ctx, query)
      if (!outcome.toast) return
      notifyFailure(item.name, outcome.toast.title)
    }
    var withSelection = function() {
      if (!parsed.needsSelection) { opened(); return }
      backend.paste(true, function(text) { ctx.selection = text; opened() })
    }
    if (parsed.needsClipboard) backend.paste(false, function(text, ok) {
      if (!ok) return notifyFailure(item.name, "The clipboard has no text to put in the link")
      ctx.clipboard = text
      withSelection()
    })
    else withSelection()
    return { close: true }
  }

  // Reads the clipboard (or the primary selection) as text: done(text, ok),
  // where ok is false when it is empty, not text, or the read timed out.
  function paste(primary, done) {
    pasteProc.collected = ""
    pasteProc.done = done
    pasteProc.command = ["timeout", "2", "wl-paste"].concat(primary ? ["--primary"] : []).concat(["--no-newline", "--type", "text"])
    pasteProc.running = true
  }

  function finishLaunch(item, ctx, query) {
    var expanded = Quicklinks.expand(item.link, ctx)
    if (expanded.error) return { toast: { style: "failure", title: expanded.error } }
    var argv = Quicklinks.openArgv(expanded.url, item.openWith, backend.paths.home)
    if (!argv) return { toast: { style: "failure", title: "Cannot open " + expanded.url } }
    backend.recordVisit("quicklink:" + item.id, query)
    Util.execArgv(argv)
    return { close: true }
  }

  function exportQuicklinks() {
    var rows = Quicklinks.exportList(quicklinksStore.doc)
    if (rows.length === 0) return { toast: { style: "failure", title: "No quicklinks to export" } }
    return backend.exportRows("quicklinks", rows)
  }

  // Writes ~/Downloads/oma-cast-<kind>-<date>.json, copies it, and reports as
  // <kind>.exported. kind: "quicklinks" or "snippets".
  function exportRows(kind, rows) {
    if (exportProc.running) return { toast: { style: "failure", title: "Already exporting" } }
    exportProc.kind = kind
    exportProc.command = ["sh", "-c", exportProc.script, "sh", kind]
    exportProc.payload = JSON.stringify(rows, null, 2) + "\n"
    exportProc.count = Array.isArray(rows) ? rows.length : 0
    exportProc.running = true
    return { toast: { style: "success", title: "Exporting…" } }
  }

  // A path the user typed, read synchronously; "" when it cannot be read.
  function readTextFile(path) {
    importFile.failed = ""
    if (importFile.path === path) importFile.reload()
    else importFile.path = path
    var text = importFile.text()
    if (importFile.failed) throw new Error("Cannot read " + path + ": " + importFile.failed)
    return text
  }

  // From a file (sync), or from the clipboard: then {pending: true} and the
  // result arrives as quicklinks.imported. Either way {ok, title, added, …}.
  function importQuicklinks(input) {
    var path = String(input || "").trim()
    if (path === "~" || path.indexOf("~/") === 0) path = backend.paths.home + path.slice(1)
    if (path && path.charAt(0) !== "/") throw new Error("Type a full path, starting with / or ~")
    if (path) return backend.importText(backend.readTextFile(path), path + " is empty")
    if (pasteProc.running) throw new Error("Still reading the clipboard")
    backend.paste(false, function(text) {
      var outcome
      try { outcome = backend.importText(text, "The clipboard is empty") }
      catch (e) { outcome = { ok: false, title: String(e.message || e) } }
      backend.emit("quicklinks.imported", outcome)
    })
    return { pending: true, ok: true, title: "Reading the clipboard…" }
  }

  function importText(text, emptyMessage) {
    if (!String(text || "").trim()) throw new Error(emptyMessage)
    var r = Quicklinks.importText(quicklinksStore.doc, text, { apps: backend.installedApps(), now: Date.now() })
    if (r.error) throw new Error(r.error)
    if (r.added > 0) backend.storeQuicklinks(r.doc)
    var parts = [r.added + " imported"]
    if (r.duplicates) parts.push(r.duplicates + " already saved")
    if (r.withoutApp) parts.push(r.withoutApp + " set to the default app")
    if (r.failed.length) parts.push("skipped " + r.failed.join(", "))
    return { ok: r.added > 0 || r.failed.length === 0, title: parts.join(" · "), added: r.added, duplicates: r.duplicates, withoutApp: r.withoutApp, failed: r.failed }
  }

  // A file or folder row (core/FileSearch.js); see RootSearch.fileActions.
  function performFileAction(candidate, action) {
    var path = candidate.path
    var folder = candidate.kind === "folder" ? path : path.slice(0, path.lastIndexOf("/")) || "/"
    switch (action) {
      case "open":
        Util.execArgv(["uwsm-app", "--", "xdg-open", path])
        return { close: true }
      case "reveal":
        // FileManager1 selects the item in Nautilus (or whichever file manager owns the name).
        Util.execArgv(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
          "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems",
          "['" + FileSearch.fileUri(path).replace(/'/g, "%27") + "']", ""])
        return { close: true }
      case "open-terminal":
        Util.execArgv(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + folder])
        return { close: true }
      case "copy-path":
        Util.execArgv(["wl-copy", "--", path])
        return { close: true, hud: "Copied Path" }
    }
    throw new Error("Unknown action " + action)
  }

  // ------------------------------------------------------------- services

  function registerServices() {
    Rpc.register(backend.registry, "system", {
      healthPing: function() { return null },
      healthDatabase: function() {
        var t0 = Date.now()
        JSON.stringify(settingsStore.doc)
        JSON.stringify(frecencyStore.doc)
        return {
          workMs: Date.now() - t0,
          settings: { loaded: settingsStore.loaded, readOnly: settingsStore.readOnly, error: settingsStore.lastError },
          frecency: { loaded: frecencyStore.loaded, readOnly: frecencyStore.readOnly, error: frecencyStore.lastError },
          quicklinks: { loaded: quicklinksStore.loaded, readOnly: quicklinksStore.readOnly, error: quicklinksStore.lastError },
          // Kept for Phase 0 callers.
          loaded: settingsStore.loaded, readOnly: settingsStore.readOnly, error: settingsStore.lastError
        }
      },
      info: function() {
        return {
          version: backend.version,
          desktop: backend.desktop,
          ready: backend.ready,
          uptimeMs: Date.now() - backend.startedAt,
          candidates: backend.candidates.length,
          appLibrary: !!backend.appLibrary,
          methods: Rpc.methods(backend.registry)
        }
      },
      getPaths: function() { return backend.paths }
    })

    Rpc.register(backend.registry, "settings", {
      getGeneralSettings: function() {
        if (!settingsStore.loaded) throw new Error("settings not loaded")
        return Schema.withGeneralDefaults(settingsStore.doc.general)
      },
      // Partial update; only known keys with a matching type (and, for
      // ranged numbers, an allowed value) are accepted.
      updateGeneralSettings: function(data) {
        if (!settingsStore.loaded) throw new Error("settings not loaded")
        if (settingsStore.readOnly) throw new Error("settings are read-only: " + (settingsStore.lastError || "written by a newer build"))
        var patch = data && typeof data === "object" ? data : {}
        var current = Schema.withGeneralDefaults(settingsStore.doc.general)
        for (var key in patch) {
          if (current[key] === undefined) throw new Error("Unknown general setting " + key)
          if (typeof patch[key] !== typeof current[key]) throw new Error("Setting " + key + " must be a " + typeof current[key])
          var choices = Schema.generalChoices[key]
          if (choices && choices.indexOf(patch[key]) < 0) throw new Error("Setting " + key + " must be one of " + choices.join(", "))
          var problem = Schema.checkGeneralValue(key, patch[key])
          if (problem) throw new Error(problem)
        }
        if (patch.launcherHotkey !== undefined) patch.launcherHotkey = backend.checkHotkey(patch.launcherHotkey, "launcher")
        settingsStore.update(function(doc) { for (var k in patch) doc.general[k] = patch[k] })
        backend.afterGeneralUpdate(patch)
        var general = Schema.withGeneralDefaults(settingsStore.doc.general)
        backend.emit("settings.generalSettingsChanged", general)
        return general
      },
      getAllCommandSettings: function() { return settingsStore.doc.commands },
      getConfig: function() { return backend.config },
      updateConfig: function(data) { return backend.updateConfig(data && typeof data === "object" ? data : {}) },
      getCommandSettings: function(data) { return settingsStore.doc.commands[String(data && data.commandId || "")] || {} },
      updateCommandSettings: function(data) {
        var id = String(data && data.commandId || "")
        if (!backend.candidatesById[id]) throw new Error("Unknown command " + id)
        var hotkey = data && data.hotkey !== undefined && data.hotkey !== null ? backend.checkHotkey(data.hotkey, id) : ""
        if (data.alias !== undefined && data.alias !== null) {
          var alias = String(data.alias).trim().toLowerCase()
          if (/\s/.test(alias)) throw new Error("An alias cannot contain spaces")
          var commands = settingsStore.doc.commands
          for (var other in commands) {
            if (other !== id && commands[other].alias === alias && alias) throw new Error("Alias “" + alias + "” is already used by " + ((backend.candidatesById[other] || {}).title || other))
          }
        }
        backend.updateCommand(id, function(s) {
          if (data.alias !== undefined) { if (data.alias) s.alias = String(data.alias).trim().toLowerCase(); else delete s.alias }
          if (data.enabled !== undefined) { if (data.enabled === false) s.enabled = false; else delete s.enabled }
          if (data.hotkey !== undefined) {
            if (hotkey) { s.hotkey = hotkey; s.hotkeyTitle = String((backend.candidatesById[id] || {}).title || id) }
            else { delete s.hotkey; delete s.hotkeyTitle }
          }
          return s
        })
        if (data.hotkey !== undefined) backend.scheduleHotkeys()
        return settingsStore.doc.commands[id] || {}
      }
    })

    Rpc.register(backend.registry, "rootSearch", {
      search: function(data) {
        var query = String(data && data.query || "")
        var view = data && data.view
        if (view && view.kind === "keybindings") {
          var matches = Keybindings.search(keybindingsSource.rows, query, Ranker)
          if (!matches.length && !keybindingsSource.error) return []
          return [{ id: "keybindings", title: backend.keybindingText(keybindingsSource.error ? "refreshError" : "section"),
            rows: matches }]
        }
        var ctx = backend.searchContext()
        // Search Files (FileSearch.js): fd results for the query, up to VIEW_LIMIT.
        if (view && view.kind === "files") {
          fileSource.request(query)
          var found = fileSource.rowsFor(query, FileSearch.VIEW_LIMIT)
          return found.length ? [{ id: "files", title: "", rows: found }] : []
        }
        var sections
        if (view && view.kind === "menu") sections = RootSearch.submenuSections(backend.candidates, view.menuId, query, ctx, backend.deps)
        else if (view && view.kind === "quicklinks") sections = RootSearch.quicklinkSections(backend.candidates, query, ctx, backend.deps)
        else if (view && view.kind === "snippets") sections = RootSearch.snippetSections(backend.candidates, query, ctx, backend.deps)
        else if (view && view.kind === "calculator-history") sections = RootSearch.historySections(calculatorStore.doc.history, query, ctx.nowMs, Calculator.filterHistory)
        else if (view && view.kind === "clipboard-history") sections = Clipboard.sections(clipboardSource.entries, query, backend.general.clipboardRows)
        else if (view && view.kind === "script-menu") {
          var menu = backend.scriptMenuFor(view)
          if (menu.error && !menu.items.length) throw new Error(menu.error)
          sections = ScriptMenu.sections(view.menuKey, menu.items, query, ctx, { Ranker: Ranker, decorate: function(c) { return RootSearch.decorate(c, ctx, backend.deps) } })
        }
        else {
          ctx.filter = String(data && data.filter || "all")
          if (query.trim() && ctx.filter === "all") ctx.calculation = backend.calculate(query)
          // A few file rows under Results; asynchronous, so they join on a
          // later rebuild (fileSource bumps candidatesRevision).
          if (ctx.filter === "all" && backend.general.rootFiles) {
            fileSource.request(query)
            ctx.files = fileSource.rowsFor(query, backend.general.fileRootLimit)
          }
          ctx.onlyFavorites = !!(data && data.onlyFavorites)
          sections = RootSearch.rootSections(backend.candidates, query, ctx, backend.deps)
        }
        return sections.map(function(s) {
          return { id: s.id, title: s.title, rows: s.rows.map(function(r) { return r.candidate }) }
        })
      },
      getActions: function(data) {
        var rowId = String(data && data.id || "")
        var file = fileSource.lookup(rowId)
        if (file) return RootSearch.actionsFor(file)
        var prefs = backend.primaryPrefs()
        if (rowId === RootSearch.CALCULATOR_ID) return RootSearch.actionsFor({ kind: "calculator" }, prefs)
        if (rowId.indexOf("calculator-history:") === 0) return RootSearch.actionsFor({ kind: "calculator-history" }, prefs)
        if (rowId.indexOf("emoji:") === 0) return RootSearch.actionsFor({ kind: "emoji" }, prefs)
        if (rowId.indexOf("clipboard:") === 0) return RootSearch.actionsFor({ kind: "clipboard" }, prefs)
        if (rowId.indexOf("fallback-quicklink:") === 0) {
          var named = backend.quicklinkNames()[rowId.slice("fallback-quicklink:".length)]
          if (!named) throw new Error("That quicklink no longer exists")
          return RootSearch.actionsFor({ kind: "fallback", title: "Open " + named })
        }
        if (rowId.indexOf("script:") === 0) return backend.scriptActions(rowId)
        var candidate = backend.decorated(rowId)
        if (!candidate && (rowId === "url:open" || rowId === "url:create"))
          return RootSearch.actionsFor({ kind: rowId === "url:open" ? "url-open" : "url-create", title: rowId === "url:open" ? "Open in Browser" : "Create Quicklink" })
        if (!candidate) {
          var fallback = RootSearch.FALLBACKS.filter(function(f) { return f.id === data.id })[0]
          if (!fallback) throw new Error("Unknown command " + (data && data.id))
          return RootSearch.actionsFor({ kind: "fallback", title: fallback.title })
        }
        var actions = RootSearch.actionsFor(candidate, prefs)
        if (candidate.kind === "keybinding") actions[0].title = backend.keybindingText("copy")
        return actions
      },
      getItemInfo: function(data) {
        var rowId = String(data && data.id || "")
        var nowMs = Date.now()
        if (rowId === RootSearch.CALCULATOR_ID) {
          var calc = backend.calculate(String(data.query || ""))
          return calc ? RootSearch.aboutFor(RootSearch.calculatorCandidate(calc), nowMs) : []
        }
        if (rowId.indexOf("calculator-history:") === 0) {
          var entry = backend.historyEntry(rowId)
          return entry ? RootSearch.aboutFor(RootSearch.historyCandidate(entry, nowMs), nowMs) : []
        }
        if (rowId.indexOf("emoji:") === 0 || rowId.indexOf("clipboard:") === 0 || rowId.indexOf("fallback-quicklink:") === 0) return []
        if (rowId.indexOf("script:") === 0 && !backend.candidatesById[rowId]) {
          var found = backend.scriptItem(rowId)
          return RootSearch.aboutFor(ScriptMenu.candidate(found.menuKey, found.item, "", "", "always"), nowMs)
        }
        var candidate = backend.decorated(rowId)
        if (!candidate) {
          var f = RootSearch.FALLBACKS.filter(function(x) { return x.id === rowId })[0]
          if (!f) throw new Error("Unknown command " + rowId)
          return RootSearch.aboutFor({ id: f.id, kind: "fallback", title: f.title, typeLabel: "Fallback", url: f.url }, nowMs)
        }
        return RootSearch.aboutFor(candidate, nowMs)
      },
      performAction: function(data) {
        // Destructive commands come back as a confirmation unless confirmed.
        if (!(data && data.confirmed)) {
          var confirm = RootSearch.confirmationFor(String(data && data.id || ""), String(data && data.action || "open"))
          if (confirm) return { confirm: confirm }
        }
        // A quicklink used as a fallback: the query fills its first argument.
        if (data && String(data.id).indexOf("fallback-quicklink:") === 0) {
          var qid = String(data.id).slice("fallback-quicklink:".length)
          var ql = Quicklinks.get(quicklinksStore.doc, qid)
          if (!ql) throw new Error("That quicklink no longer exists")
          var parsedLink = Quicklinks.parseLink(ql.link)
          var values = ({})
          if (!parsedLink.error && parsedLink.arguments.length) values[parsedLink.arguments[0].name] = String(data.query || "").trim()
          return backend.openQuicklink(qid, values, "")
        }
        var fallback = RootSearch.FALLBACKS.filter(function(f) { return f.id === (data && data.id) })[0]
        if (fallback) {
          if (fallback.id === Agent.FALLBACK_ID) {
            agentLauncher.start(data.query)
            return { pending: true }
          }
          Util.execArgv(["omarchy-launch-browser", RootSearch.fallbackUrl(fallback, data.query)])
          return { close: true }
        }
        var file = fileSource.lookup(String(data && data.id || ""))
        if (file) return backend.performFileAction(file, String(data.action || "open"))
        // So are the rows for a typed web address.
        var url = data && (data.id === "url:open" || data.id === "url:create") ? Quicklinks.webAddress(data.query) : ""
        if (url && data.id === "url:open") {
          var argv = Quicklinks.openArgv(url, "", backend.paths.home)
          if (!argv) return { toast: { style: "failure", title: "Cannot open " + url } }
          Util.execArgv(argv)
          return { close: true }
        }
        if (url) return { push: backend.quicklinkForm("Create Quicklink", Quicklinks.suggestion(data.query)) }
        // The calculator row is the query itself, evaluated again.
        if (data && data.id === RootSearch.CALCULATOR_ID) {
          var calc = backend.calculate(String(data.query || ""))
          if (!calc) throw new Error("Nothing to calculate")
          return backend.calculatorAction(String(data.action || "open"), { query: calc.input, result: calc.result, copy: calc.copy, kind: calc.kind }, "")
        }
        if (data && String(data.id).indexOf("calculator-history:") === 0) {
          var entry = backend.historyEntry(data.id)
          if (!entry) throw new Error("No such history entry")
          return backend.calculatorAction(String(data.action || "open"), entry, entry.id)
        }
        if (data && String(data.id).indexOf("emoji:") === 0) return backend.emojiAction(String(data.action || "open"), String(data.id).slice("emoji:".length))
        if (data && String(data.id).indexOf("clipboard:") === 0) return backend.clipboardAction(String(data.action || "open"), backend.clipboardEntry(data.id))
        if (data && String(data.id).indexOf("script:") === 0) return backend.scriptAction(data)
        return backend.performAction(data)
      },
      getSearchHistory: function() { return frecencyStore.loaded ? frecencyStore.doc.searchHistory : [] },
      // The detail pane beside clipboard and script-menu lists; null for none.
      getDetail: function(data) {
        var rowId = String(data && data.id || "")
        if (rowId.indexOf("clipboard:") === 0) return Clipboard.detail(backend.clipboardEntry(rowId))
        if (rowId.indexOf("snippet:") === 0) {
          var snippet = Snippets.get(snippetsStore.doc, rowId.slice("snippet:".length))
          return snippet ? Snippets.detail(snippet, function(ms) { return RootSearch.relativeTime(ms, Date.now()) }) : null
        }
        if (rowId.indexOf("script:") === 0) return backend.scriptDetail(rowId)
        return null
      }
    })

    // Names from Raycast's snippets namespace (ref 02 §2).
    Rpc.register(backend.registry, "snippets", {
      list: function() { return Snippets.list(snippetsStore.doc) },
      get: function(data) { return Snippets.get(snippetsStore.doc, String(data && data.id || "")) },
      save: function(data) {
        var r = Snippets.save(snippetsStore.doc, data || {}, { now: Date.now() }, backend.snippetDeps)
        if (r.error) throw new Error(r.error)
        backend.storeSnippets(r.doc)
        return r.item
      },
      update: function(data) {
        var r = Snippets.update(snippetsStore.doc, String(data && data.id || ""), data || {}, { now: Date.now() }, backend.snippetDeps)
        if (r.error) throw new Error(r.error)
        backend.storeSnippets(r.doc)
        return r.item
      },
      "delete": function(data) {
        var id = String(data && data.id || "")
        var r = Snippets.remove(snippetsStore.doc, id)
        if (r.error) throw new Error(r.error)
        backend.storeSnippets(r.doc)
        // The row's alias, favourite and ranking go with it.
        settingsStore.update(function(doc) { delete doc.commands["snippet:" + id] })
        frecencyStore.update(function(doc) { delete doc.items["snippet:" + id] })
        return null
      },
      importText: function(data) {
        var r = Snippets.importText(snippetsStore.doc, String(data && data.text || ""), { now: Date.now() }, backend.snippetDeps)
        if (r.error) throw new Error(r.error)
        if (r.added > 0) backend.storeSnippets(r.doc)
        return { added: r.added, duplicates: r.duplicates, failed: r.failed }
      },
      exportText: function() { return JSON.stringify(Snippets.exportList(snippetsStore.doc), null, 2) },
      // {path?}: a JSON file, or the clipboard when empty; as quicklinks.import.
      "import": function(data) { return backend.importSnippets(data && data.path) },
      "export": function() {
        var rows = Snippets.exportList(snippetsStore.doc)
        if (rows.length === 0) return { toast: { style: "failure", title: "No snippets to export" } }
        return backend.exportRows("snippets", rows)
      },
      // Checks a draft without saving it (the Settings editor shows the error).
      check: function(data) {
        var r = Snippets.validate(snippetsStore.doc, data || {}, String(data && data.id || ""), backend.snippetDeps)
        return r.error
      }
    })

    Rpc.register(backend.registry, "hotkeys", {
      status: function() { return backend.hotkeyStatus() },
      // {hotkey} -> titles of Omarchy bindings on the same keys.
      conflicts: function(data) { return backend.hotkeyConflicts(String(data && data.hotkey || "")) },
      // Rewrites oma-cast.lua now (`oma-cast setup hyprland` calls this).
      write: function() { return backend.writeHotkeys(true) },
      // {active}: Settings records a hotkey inside an empty submap, so combos
      // Hyprland already binds reach it.
      record: function(data) {
        Quickshell.execDetached(["hyprctl", "dispatch", data && data.active ? "hl.dsp.submap(\"oma-cast-record\")" : "hl.dsp.submap(\"reset\")"])
        return null
      }
    })

    Rpc.register(backend.registry, "data", {
      clearSearchHistory: function() { frecencyStore.update(function(doc) { doc.searchHistory = [] }); return null },
      resetRankings: function() { frecencyStore.update(function(doc) { doc.items = ({}) }); return null },
      clearEmojiRecents: function() { emojiStore.update(function(doc) { doc.usage = ({}) }); return null },
      backup: function() { return backend.exportRows("backup", backend.backupDocument()) },
      // {path?}: a backup file, or the clipboard when empty.
      restore: function(data) { return backend.restoreFrom(data && data.path) }
    })

    Rpc.register(backend.registry, "emoji", {
      // Grid rows for the emoji view (Emoji.grid).
      grid: function(data) {
        var usage = emojiStore.loaded ? emojiStore.doc.usage : ({})
        return Emoji.grid(emojiSource.values, String(data && data.query || ""), usage, Number(data && data.columns) || 8, backend.general.emojiFrequentCount)
      }
    })

    Rpc.register(backend.registry, "scriptMenu", {
      // ↵ in a script-input view: run the item or action with {input} filled.
      submitInput: function(data) {
        var found = backend.scriptItem(String(data && data.rowId || ""))
        var target = ScriptMenu.targetFor(found.item, String(data.actionId || "open"))
        return backend.runScriptPlan(ScriptMenu.planInput(target, String(data.input || "")), target ? target.label : "")
      },
      refresh: function() { backend.refreshScriptMenus(); return null }
    })

    Rpc.register(backend.registry, "quicklinks", {
      list: function() { return Quicklinks.list(quicklinksStore.doc) },
      get: function(data) { return Quicklinks.get(quicklinksStore.doc, String(data && data.id || "")) },
      openWithChoices: function(data) { return Quicklinks.openWithChoices(backend.installedApps(), data && data.query, data && data.current) },
      openWithLabel: function(data) { return Quicklinks.openWithLabel(backend.installedApps(), String(data && data.id || "")) },
      // {name, link, iconName?, openWith?}
      save: function(data) {
        var r = Quicklinks.save(quicklinksStore.doc, data || {}, { apps: backend.installedApps(), now: Date.now() })
        if (r.error) throw new Error(r.error)
        backend.storeQuicklinks(r.doc)
        return r.item
      },
      // {id, name, link, iconName?, openWith?}
      update: function(data) {
        var r = Quicklinks.update(quicklinksStore.doc, String(data && data.id || ""), data || {}, { apps: backend.installedApps(), now: Date.now() })
        if (r.error) throw new Error(r.error)
        backend.storeQuicklinks(r.doc)
        return r.item
      },
      // Also forgets its alias, favourite slot and ranking.
      "delete": function(data) {
        var id = String(data && data.id || "")
        var r = Quicklinks.remove(quicklinksStore.doc, id)
        if (r.error) throw new Error(r.error)
        backend.storeQuicklinks(r.doc)
        if (settingsStore.doc.commands["quicklink:" + id]) backend.updateCommand("quicklink:" + id, function() { return {} })
        frecencyStore.update(function(doc) { delete doc.items["quicklink:" + id] })
        return null
      },
      // {path?}: a JSON file, or the clipboard when empty.
      "import": function(data) { return backend.importQuicklinks(data && data.path) },
      "export": function() { return backend.exportQuicklinks() },
      // {id, values?, query?}
      open: function(data) {
        var item = Quicklinks.get(quicklinksStore.doc, String(data && data.id || ""))
        if (!item) throw new Error("Quicklink not found")
        return backend.launchQuicklink(item, (data && data.values) || {}, String(data && data.query || ""))
      }
    })

    // Names from Raycast's calculator namespace (ref 02 §2).
    Rpc.register(backend.registry, "calculator", {
      calculate: function(data) { return backend.calculate(String(data && data.query || "")) },
      historyGetAll: function() { return calculatorStore.loaded ? calculatorStore.doc.history : [] },
      historyDelete: function(data) { return backend.calculatorAction("delete-entry", null, String(data && data.id || "")) },
      historyDeleteAll: function() { return backend.calculatorAction("delete-all-entries", null, "") },
      refreshCurrencies: function() {
        if (!backend.config.currencyRates) throw new Error("currencyRates is off in config.json")
        calculatorData.fetchRates()
        return null
      },
      getCurrencies: function() {
        var r = calculatorData.rates
        return {
          enabled: backend.config.currencyRates,
          date: r ? r.date : null,
          base: r ? r.base : null,
          currencies: r ? Object.keys(r.rates).concat([r.base]).sort() : [],
          // {code: "US Dollar (USD)"} for every currency with a rate.
          names: (function() {
            var out = ({})
            var codes = r ? Object.keys(r.rates).concat([r.base]) : []
            for (var i = 0; i < codes.length; i++) if (Calculator.CURRENCIES[codes[i]]) out[codes[i]] = Calculator.currencyName(codes[i])
            return out
          })(),
          home: backend.homeCurrency(),
          second: backend.secondCurrency(),
          locale: Qt.locale().name,
          fetchedAt: calculatorData.ratesFetchedAt || null,
          zones: Object.keys(calculatorData.zones).length
        }
      }
    })

    Rpc.register(backend.registry, "frecency", {
      visit: function(data) { backend.recordVisit(String(data.id), String(data.query || "")); return null },
      get: function(data) {
        var entry = frecencyStore.doc.items[String(data && data.id || "")]
        return entry ? { anchor: entry.anchor, openedAt: entry.openedAt, score: Frecency.score(entry.anchor, Date.now() / 1000), searchTerms: entry.searchTerms } : null
      }
    })
  }

  Component.onCompleted: {
    try {
      var strings = Qt.createQmlObject('import qs.Commons; Translations {}', backend)
      strings.directory = Qt.resolvedUrl("i18n")
      strings.stringsChanged.connect(function() { rebuildTimer.restart() })
      strings.languageChanged.connect(function() { keybindingsSource.refresh() })
      backend.keybindingStrings = strings
    } catch (e) { /* Omarchy 4.0.5: use the bundled English strings. */ }
    registerServices()
    mkdirs.running = true
  }

  onAppLibraryChanged: rebuildTimer.restart()

  Connections {
    target: backend.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { rebuildTimer.restart() }
  }

  Connections {
    target: backend.appLibrary ? null : DesktopEntries.applications
    ignoreUnknownSignals: true
    function onValuesChanged() { rebuildTimer.restart() }
  }

  Component.onDestruction: { settingsStore.flush(); frecencyStore.flush(); calculatorStore.flush(); emojiStore.flush(); quicklinksStore.flush(); snippetsStore.flush() }
  onNotification: function(method, data) {
    if (method === "window.visibilityChanged" && data && data.visible) {
      menuSource.refresh()
      calculatorData.refresh()
      backend.refreshScriptMenus()
      keybindingsSource.refresh()
    }
    if (method === "window.visibilityChanged" && data && !data.visible) agentLauncher.cancel()
  }

  AppFocuser {
    id: appFocuser
    onLaunchRequested: function(candidate) { backend.launchApp(candidate) }
  }

  AgentLauncher {
    id: agentLauncher
    onPrepared: function(argv) { backend.emit("agent.launchReady", { argv: argv }) }
    onFailed: function(message) { backend.emit("agent.launchFailed", { message: message }) }
  }


  Process {
    id: mkdirs
    command: ["mkdir", "-p"].concat(Paths.directoriesToCreate(backend.paths))
    onExited: function(exitCode) {
      if (exitCode !== 0) backend.log("error", "paths", "could not create data directories", { exitCode: exitCode })
      backend.directoriesReady = true
    }
  }

  OmarchyMenuSource {
    id: menuSource
    onRevisionChanged: rebuildTimer.restart()
    onMessage: function(level, text, metadata) { backend.log(level, "omarchy-menu", text, metadata) }
  }

  KeybindingsSource {
    id: keybindingsSource
    onRevisionChanged: rebuildTimer.restart()
  }

  FileSearchSource {
    id: fileSource
    options: ({ folders: backend.general.fileFolders, hidden: backend.general.fileHidden, excludes: backend.general.fileExcludes })
    onRevisionChanged: backend.candidatesRevision++
    onMessage: function(level, text, metadata) { backend.log(level, "files", text, metadata) }
  }

  JsonStore {
    id: settingsStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.settings.file
    migrations: Schema.documents.settings.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  JsonStore {
    id: frecencyStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.frecency.file
    migrations: Schema.documents.frecency.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  JsonStore {
    id: calculatorStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.calculator.file
    migrations: Schema.documents.calculator.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  JsonStore {
    id: emojiStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.emoji.file
    migrations: Schema.documents.emoji.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  EmojiSource {
    id: emojiSource
    onValuesChanged: backend.viewRevision++
    onMessage: function(level, text, metadata) { backend.log(level, "emoji", text, metadata) }
  }

  ClipboardSource {
    id: clipboardSource
    onRevisionChanged: backend.viewRevision++
  }

  ScriptRunner {
    id: scriptRunner
  }

  TextPaster {
    id: textPaster
  }

  JsonStore {
    id: snippetsStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.snippets.file
    migrations: Schema.documents.snippets.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }
  Connections { target: snippetsStore; function onChanged() { backend.storeRevision++; rebuildTimer.restart() } }

  CalculatorData {
    id: calculatorData
    cacheDir: backend.directoriesReady ? backend.paths.cache : ""
    ratesEnabled: backend.config.currencyRates
    onMessage: function(level, text, metadata) { backend.log(level, "calculator", text, metadata) }
  }

  JsonStore {
    id: quicklinksStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.quicklinks.file
    migrations: Schema.documents.quicklinks.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  // wl-paste goes through the data-control protocol, so it works while the
  // launcher is unfocused or closed. Quickshell.clipboardText would not.
  Process {
    id: pasteProc
    property var done: null
    property string collected: ""
    stdout: SplitParser { onRead: function(line) { pasteProc.collected += line + "\n" } }
    onExited: function(exitCode) {
      var done = pasteProc.done
      pasteProc.done = null
      if (done) done(exitCode === 0 ? pasteProc.collected.replace(/\n$/, "") : "", exitCode === 0)
    }
  }

  // Export: a JSON file in Downloads (or home), also put on the clipboard.
  // The JSON goes through stdin, so no file contents reach an argv.
  Process {
    id: exportProc
    property string payload: ""
    property int count: 0
    property string kind: "quicklinks"
    readonly property string script: "d=$(xdg-user-dir DOWNLOAD 2>/dev/null); [ -d \"$d\" ] || d=$HOME; f=\"$d/oma-cast-$1-$(date +%F).json\"; cat > \"$f\" && wl-copy --type text/plain < \"$f\" && printf %s \"$f\""
    stdinEnabled: true
    property string path: ""
    property string errors: ""
    stdout: SplitParser { onRead: function(line) { exportProc.path = line } }
    stderr: SplitParser { onRead: function(line) { exportProc.errors = line } }
    onStarted: { exportProc.write(exportProc.payload); exportProc.stdinEnabled = false }
    onExited: function(exitCode) {
      exportProc.stdinEnabled = true
      var where = exportProc.path.replace(backend.paths.home, "~")
      var noun = exportProc.kind === "snippets" ? "snippet" : "quicklink"
      backend.emit(exportProc.kind + ".exported", exitCode === 0
        ? { ok: true, title: exportProc.kind === "backup" ? "Saved a backup to " + where + " and the clipboard"
            : "Exported " + exportProc.count + " " + noun + (exportProc.count === 1 ? "" : "s") + " to " + where + " and the clipboard" }
        : { ok: false, title: "Export failed: " + (exportProc.errors || "exit " + exitCode) })
      exportProc.path = ""
      exportProc.errors = ""
    }
  }

  FileView {
    id: importFile
    property string failed: ""
    blockAllReads: true
    printErrors: false
    onLoadFailed: function(error) { importFile.failed = FileViewError.toString(error) }
  }

  // Bumped whenever ranking inputs change, so views re-query.
  readonly property int dataRevision: candidatesRevision + (settingsStore.loaded ? 1 : 0) + (frecencyStore.loaded ? 1 : 0)
  property int storeRevision: 0
  Connections { target: settingsStore; function onChanged() { backend.storeRevision++ } }
  Connections { target: frecencyStore; function onChanged() { backend.storeRevision++ } }
  Connections { target: quicklinksStore; function onChanged() { backend.storeRevision++; rebuildTimer.restart() } }
  Connections { target: calculatorStore; function onChanged() { backend.storeRevision++ } }
  Connections { target: emojiStore; function onChanged() { backend.storeRevision++ } }

  FileView {
    id: configFile
    property bool loaded: false
    path: backend.directoriesReady ? backend.paths.configFile : ""
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      configFile.loaded = true
      try {
        backend.config = Schema.withConfigDefaults(JSON.parse(text()))
      } catch (e) {
        backend.config = Schema.withConfigDefaults(null)
        backend.log("warning", "config", "ignoring unreadable " + path + ": " + e)
      }
    }
    onLoadFailed: { configFile.loaded = false; backend.config = Schema.withConfigDefaults(null) }
  }
}
