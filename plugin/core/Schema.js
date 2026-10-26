
var settingsMigrations = [
  {
    version: 1,
    name: "general-settings",
    up: function(doc) {
      doc.general = {
        windowMode: "expanded",
        showFavoritesInCompactMode: true,
        windowPresentationMode: "mouse-screen",
        popToRootTimeout: 90,
        escapeKeyBehavior: "pop-back-or-close",
        navigationBindings: "emacs",
        rootSearchSensitivity: "medium",
        uiZoom: 1,
        theme: "omarchy"
      }
      doc.commands = {}
      return doc
    }
  }
]

var frecencyMigrations = [
  {
    version: 1,
    name: "frecency",
    up: function(doc) {
      doc.items = {}
      doc.searchHistory = []
      return doc
    }
  }
]

// Calculator History (SPEC §6.4 calculator_history), capped and pruned by
// Calculator.pushHistory.
var calculatorMigrations = [
  {
    version: 1,
    name: "calculator-history",
    up: function(doc) {
      doc.history = []          // newest first: {id, query, result, copy, kind, createdAt}
      return doc
    }
  }
]

// Emoji usage for "Frequently Used" (Emoji.recordUsage), keyed "$<emoji>".
var emojiMigrations = [
  {
    version: 1,
    name: "emoji-usage",
    up: function(doc) {
      doc.usage = {}            // {"$😀": {count, lastUsedAt}}
      return doc
    }
  }
]

// Saved quicklinks (SPEC §8.4), in the shape Quicklinks.js reads:
// items [{id, name, link, iconName, openWith, createdAt, updatedAt}].
var quicklinksMigrations = [
  {
    version: 1,
    name: "quicklinks",
    up: function(doc) {
      doc.items = Array.isArray(doc.items) ? doc.items : []
      return doc
    }
  }
]

// Saved snippets (fork, SPEC §8.3): items [{id, name, text, keyword,
// createdAt, updatedAt}], in the shape Snippets.js reads.
var snippetsMigrations = [
  {
    version: 1,
    name: "snippets",
    up: function(doc) {
      doc.items = Array.isArray(doc.items) ? doc.items : []
      return doc
    }
  }
]

var SEARCH_HISTORY_LIMIT = 20

function pushSearchHistory(history, query) {
  var q = String(query || "").trim()
  var list = Array.isArray(history) ? history.slice() : []
  if (!q) return list
  list = list.filter(function(item) { return item !== q })
  list.unshift(q)
  return list.slice(0, SEARCH_HISTORY_LIMIT)
}

var documents = {
  settings: { file: "settings.json", migrations: settingsMigrations },
  frecency: { file: "frecency.json", migrations: frecencyMigrations },
  calculator: { file: "calculator.json", migrations: calculatorMigrations },
  emoji: { file: "emoji.json", migrations: emojiMigrations },
  quicklinks: { file: "quicklinks.json", migrations: quicklinksMigrations },
  snippets: { file: "snippets.json", migrations: snippetsMigrations }
}

// General settings added after the v1 migration. They are filled in on read
// (withGeneralDefaults), so an additive setting needs no migration and cannot
// collide with another branch's migration number. [D]
var generalAdditions = {
  windowWidth: 750,                           // launcher card at uiZoom 1, px [O 750×475, SPEC §5.1]
  windowHeight: 475
}

// Inclusive bounds for numeric general settings. The card is also clamped to
// the screen when drawn, so these only reject nonsense. [D]
var generalRanges = {
  windowWidth: [500, 3000],
  windowHeight: [300, 2000]
}

function withGeneralDefaults(general) {
  var out = {}
  if (general && typeof general === "object" && !Array.isArray(general)) {
    for (var k in general) out[k] = general[k]
  }
  for (var key in generalAdditions) {
    if (typeof out[key] !== typeof generalAdditions[key]) out[key] = generalAdditions[key]
  }
  return out
}

// null when `value` is acceptable for general setting `key`, else the reason.
function checkGeneralValue(key, value) {
  var range = generalRanges[key]
  if (!range) return null
  if (typeof value !== "number" || !isFinite(value) || Math.round(value) !== value)
    return "Setting " + key + " must be a whole number"
  if (value < range[0] || value > range[1])
    return "Setting " + key + " must be between " + range[0] + " and " + range[1]
  return null
}

// Host flags in $XDG_CONFIG_HOME/oma-cast/config.json: user-editable and
// non-secret (SPEC §6.3). Not migrated; unknown keys are kept and ignored,
// missing ones fall back to these defaults.
var configDefaults = {
  logLevel: "info",
  keepVisibleOnFocusLoss: false,
  // Daily ECB reference rates from frankfurter.dev for currency conversion
  // (SPEC §8 Calculator). The only network request oma-cast makes. [D]
  currencyRates: true,
  // Calculator preferences named after Raycast's (ref 04 App. B) [O].
  remToPxRate: 16,
  workHoursPerDay: 8,
  // "auto" follows the Qt locale; "12h" or "24h" forces a clock. [D]
  clockFormat: "auto"
}

// Values a config key or general setting may take, beyond its type.
var configChoices = {
  clockFormat: ["auto", "12h", "24h"]
}

var generalChoices = {
  windowMode: ["expanded", "compact"],
  escapeKeyBehavior: ["pop-back-or-close", "close-and-pop-to-root"],
  navigationBindings: ["emacs", "vim-motions"],
  rootSearchSensitivity: ["low", "medium", "high"]
}

function validConfigValue(key, value) {
  if (typeof value !== typeof configDefaults[key]) return false
  if (configChoices[key]) return configChoices[key].indexOf(value) >= 0
  if (typeof value === "number") return isFinite(value) && value > 0
  return true
}

function withConfigDefaults(value) {
  var out = {}
  for (var key in configDefaults) out[key] = configDefaults[key]
  if (value && typeof value === "object" && !Array.isArray(value)) {
    for (var k in value) {
      if (configDefaults[k] !== undefined && validConfigValue(k, value[k])) out[k] = value[k]
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    settingsMigrations: settingsMigrations,
    frecencyMigrations: frecencyMigrations,
    quicklinksMigrations: quicklinksMigrations,
    calculatorMigrations: calculatorMigrations,
    emojiMigrations: emojiMigrations,
    snippetsMigrations: snippetsMigrations,
    pushSearchHistory: pushSearchHistory,
    SEARCH_HISTORY_LIMIT: SEARCH_HISTORY_LIMIT,
    documents: documents,
    generalAdditions: generalAdditions,
    generalRanges: generalRanges,
    withGeneralDefaults: withGeneralDefaults,
    checkGeneralValue: checkGeneralValue,
    configDefaults: configDefaults,
    generalChoices: generalChoices,
    withConfigDefaults: withConfigDefaults
  }
}
