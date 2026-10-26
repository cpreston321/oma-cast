const test = require("node:test")
const assert = require("node:assert/strict")
const C = require("../plugin/core/Calculator.js")
const RS = require("../plugin/core/RootSearch.js")

// Monday 19 Oct 2026, 16:06 in New York (UTC-4). Dates use the process
// zone, so pin it.
process.env.TZ = "America/New_York"
const NOW = Date.UTC(2026, 9, 19, 20, 6)
const env = {
  nowMs: NOW, localOffset: -240, hour12: true,
  rates: { base: "EUR", date: "2026-10-19", rates: { USD: 1.1225, GBP: 0.84205, JPY: 177.63 } },
  zones: { "Asia/Tokyo": 540, "Europe/London": 60, "America/New_York": -240 }
}
const result = (q, e) => { const r = C.evaluate(q, e || env); return r && r.result }

test("arithmetic, precedence, functions and constants", () => {
  assert.equal(result("2+2"), "4")
  assert.equal(result("2 + 3 * 4"), "14")
  assert.equal(result("3(4+5)"), "27")
  assert.equal(result("-2^2"), "-4")
  assert.equal(result("2^10"), "1,024")
  assert.equal(result("2^40"), "1,099,511,627,776", "integers stay exact")
  assert.equal(result("5!"), "120")
  assert.equal(result("10 mod 3"), "1")
  assert.equal(result("10 % 3"), "1", "% before an operand is modulo")
  assert.equal(result("sqrt 16"), "4")
  assert.equal(result("sin(30°)"), "0.5")
  assert.equal(result("0.1+0.2"), "0.3")
  assert.equal(result("1/3"), "0.333333333333")
  assert.equal(result("max(100,200)"), "200", "commas inside calls separate arguments")
  assert.equal(result("1,000,000 * 3"), "3,000,000")
  assert.equal(result("2 × 3 ÷ 4"), "1.5")
  assert.equal(result("pi"), "3.14159265359")
})

test("anything that is not a calculation yields no row", () => {
  // A lone amount and unit ("5 kg") converts to its counterpart (fork); see below.
  for (const q of ["", "firefox", "42", "-5", "e", "1password", "7zip", "now", "time", "may", "20%", "to do", "kg", "x", "1st", "kilogram", "4k", "2fa", "3d"]) {
    assert.equal(C.evaluate(q, env), null, q)
  }
})

test("Soulver-style percentages", () => {
  assert.equal(result("20% of 50"), "10")
  assert.equal(result("20% off 50"), "40")
  assert.equal(result("20% on 50"), "60")
  assert.equal(result("$30 + 20%"), "$36.00")
  assert.equal(result("100 - 15%"), "85")
  assert.equal(result("50 as a % of 200"), "25%")
  assert.equal(result("$5k + 10%"), "$5,500.00")
})

test("unit conversions", () => {
  assert.equal(result("5 ft to cm"), "152.4 cm")
  assert.equal(result("5 ft in cm"), "152.4 cm", "in after a unit is the conversion word")
  assert.equal(result("12 in to cm"), "30.48 cm", "in after a number is inches")
  assert.equal(result("100 °F to °C"), "37.7778 °C")
  assert.equal(result("100f to c"), "37.7778 °C")
  assert.equal(result("1 GiB to MB"), "1,073.7418 MB")
  assert.equal(result("16px to rem"), "1 rem")
  assert.equal(result("90 min to hours"), "1.5 hours")
  assert.equal(result("5 m^2 to ft^2"), "53.8196 ft²")
  assert.equal(result("1 sq mi to acres"), "640 ac")
  assert.equal(result("kg to lb"), "2.2046 lb")
  assert.equal(C.evaluate("5 kg to cm", env), null, "incompatible units")
})

test("units combine through arithmetic", () => {
  assert.equal(result("3 m * 4 m"), "12 m²")
  assert.equal(result("10 km / 2 h"), "5 km/h")
  assert.equal(result("60 mph * 2 h"), "120 mi")
  assert.equal(result("5 kW * 3 h"), "15 kWh")
  assert.equal(result("5 ft + 6 in"), "5.5 ft")
  assert.equal(result("$30/h * 8 h"), "$240.00")
})

test("currencies use the rates and need them only to convert", () => {
  assert.equal(result("10 usd to eur"), "€8.91")
  assert.equal(result("€30 in £"), "£25.26")
  assert.equal(result("1000 yen to usd"), "$6.32")
  assert.equal(C.evaluate("10 usd to eur", Object.assign({}, env, { rates: null })), null)
  assert.equal(result("$30 + 20%", Object.assign({}, env, { rates: null })), "$36.00")
})

test("dates and durations", () => {
  assert.equal(result("3 days from now"), "Thursday, 22 October 2026 at 4:06 PM")
  assert.equal(result("2 weeks ago"), "Monday, 5 October 2026 at 4:06 PM")
  assert.equal(result("days until christmas"), "67 days", "whole days across the DST switch")
  assert.equal(result("christmas - today"), "67 days")
  assert.equal(result("2026-12-25 + 1 week"), "Friday, 1 January 2027")
  assert.equal(result("next friday + 1 day"), "Saturday, 24 October 2026")
  assert.equal(C.evaluate("christmas - today", env).kind, "date")
})

test("time zones", () => {
  assert.equal(result("time in tokyo"), "5:06 AM (+1 day)")
  assert.equal(result("tokyo time"), "5:06 AM (+1 day)")
  assert.equal(result("3pm london to new york"), "10:00 AM")
  assert.equal(result("3pm in tokyo"), "4:00 AM (+1 day)")
  assert.equal(result("15:00 utc in nyc", Object.assign({}, env, { hour12: false })), "11:00")
  assert.equal(C.evaluate("time in tokyo", Object.assign({}, env, { zones: {} })), null, "no offsets yet")
})

test("bases", () => {
  assert.equal(result("255 to hex"), "0xFF")
  assert.equal(result("10 in binary"), "0b1010")
  assert.equal(result("0xff + 1"), "256")
})

test("captions and copy text", () => {
  const r = C.evaluate("5 ft to cm", env)
  assert.equal(r.inputCaption, "Feet")
  assert.equal(r.resultCaption, "Centimeters")
  assert.equal(r.copy, "152.4 cm")
  assert.equal(C.evaluate("1000 + 234", env).resultCaption, "One Thousand Two Hundred Thirty-four")
  assert.equal(C.evaluate("1000 + 234", env).copy, "1234", "copy has no grouping")
  assert.equal(C.words(-21), "Minus Twenty-one")
})

test("mixed units add up", () => {
  assert.equal(result("5 ft 3 in"), "160.02 cm", "a lone height converts to cm (fork)")
  assert.equal(result("5 ft 3 in + 0 in"), "5.25 ft")
  assert.equal(result("5 ft 3 in to cm"), "160.02 cm")
  assert.equal(result("1 m 50 cm"), "1.5 m")
  assert.equal(result("1 h 30 min + 45 min"), "2.25 hours")
  assert.match(result("3 days 4 hours from now"), /^Thursday, 22 October 2026 at 8:06 PM$/)
  for (const q of ["2 kg 3", "10 usd 5 usd", "100 °F 3 °C"]) assert.equal(C.evaluate(q, env), null, q)
})

test("work time follows workHoursPerDay and remToPxRate is configurable", () => {
  assert.equal(result("40 hours in work days"), "5 work days")
  assert.equal(result("2 work weeks to hours"), "80 hours")
  assert.equal(result("15 hours in workdays", { ...env, workHoursPerDay: 7.5 }), "2 work days")
  assert.equal(result("16px to rem", { ...env, remToPxRate: 10 }), "1.6 rem")
  assert.equal(C.evaluate("3 workdays from now", env), null, "work days are not calendar days")
})

test("unix timestamps", () => {
  const stamp = C.evaluate("unix 1700000000", env)
  assert.equal(stamp.result, "Tuesday, 14 November 2023 at 5:13 PM")
  assert.equal(stamp.inputCaption, "Unix Timestamp")
  assert.equal(result("1700000000 to date"), stamp.result)
  assert.equal(result("1700000000000 to date"), stamp.result, "13 digits are milliseconds")
  assert.equal(result("timestamp 1700000000"), stamp.result)
  const now = C.evaluate("now to unix", env)
  assert.deepEqual([now.result, now.copy, now.resultCaption], [String(NOW / 1000), String(NOW / 1000), "Unix Timestamp"])
  assert.equal(result("unix time"), String(NOW / 1000))
  assert.equal(result("unix now"), String(NOW / 1000))
  assert.equal(result("2023-11-14 to unix"), "1699938000")
  for (const q of ["unix", "epoch", "timestamp", "date"]) assert.equal(C.evaluate(q, env), null, q)
})

test("history is newest first, unique, pruned after 90 days and capped", () => {
  let h = []
  h = C.pushHistory(h, { id: "1", query: "2+2", result: "4", copy: "4", kind: "math" }, NOW - 100 * 864e5)
  h = C.pushHistory(h, { id: "2", query: "5 ft to cm", result: "152.4 cm", copy: "152.4 cm", kind: "conversion" }, NOW)
  assert.deepEqual(h.map((e) => e.id), ["2"], "the 100-day-old entry is gone")
  h = C.pushHistory(h, { id: "3", query: "3*3", result: "9", copy: "9", kind: "math" }, NOW)
  h = C.pushHistory(h, { id: "4", query: "5 ft to cm", result: "152.4 cm", copy: "152.4 cm", kind: "conversion" }, NOW)
  assert.deepEqual(h.map((e) => e.id), ["4", "3"])
  assert.deepEqual(C.filterHistory(h, "cm").map((e) => e.id), ["4"])
  let big = []
  for (let i = 0; i < C.HISTORY_LIMIT + 5; i++) big = C.pushHistory(big, { id: String(i), query: "q" + i, result: "", copy: "", kind: "math" }, NOW)
  assert.equal(big.length, C.HISTORY_LIMIT)
})

test("root search puts the Calculator section first; ↵ copies, Ctrl ↵ pastes", () => {
  const deps = { Ranker: require("../plugin/core/Ranker.js"), Frecency: require("../plugin/core/Frecency.js"), OmarchyMenu: require("../plugin/core/OmarchyMenu.js") }
  const ctx = { commands: {}, frecency: {}, nowMs: NOW, sensitivity: "medium", calculation: C.evaluate("2+2", env) }
  const sections = RS.rootSections(RS.BUILTINS.map(RS.builtinCandidate), "2+2", ctx, deps)
  assert.equal(sections[0].id, "calculator")
  assert.equal(sections[0].rows[0].candidate.calcResult, "4")
  assert.equal(sections.at(-1).id, "fallback-commands")
  assert.deepEqual(sections.at(-1).rows.map((r) => r.candidate.id), ["fallback:google", "fallback:duckduckgo", "fallback:agent"])
  const actions = RS.actionsFor({ kind: "calculator" }).map((a) => a.id)
  assert.deepEqual(actions.slice(0, 2), ["copy-answer", "paste-answer"])
  const calcHistory = RS.rootSections(RS.BUILTINS.map(RS.builtinCandidate), "calc hist", { commands: {}, frecency: {}, nowMs: NOW }, deps)
  assert.equal(calcHistory[0].rows[0].candidate.title, "Calculator History")
})

// ---- fork: everyday conversions

test("a lone amount and unit converts to its counterpart", () => {
  for (const [q, want] of [
    ["16rem", "256 px"], ["1.5rem", "24 px"], ["24px", "1.5 rem"], ["5 kg", "11.0231 lb"], ["150 lbs", "68.0389 kg"],
    ["100 f", "37.7778 °C"], ["37c", "98.6 °F"], ["300 k", "26.85 °C"], ["10 km", "6.2137 mi"], ["1 in", "2.54 cm"],
    ["2 l", "0.5283 gal"], ["500 GB", "465.6613 GiB"], ["30 psi", "2.0684 bar"], ["180°", "3.1416 rad"]
  ]) assert.equal(result(q), want, q)
})

test("heights: feet and inch marks, 5ft10, and a feet-and-inches target", () => {
  for (const q of [`5'10"`, "5′10″", "5ft10", "5 ft 10", "5 ft 10 in"]) assert.equal(result(q), "177.8 cm", q)
  assert.equal(result(`5'10" to m`), "1.778 m")
  assert.equal(result("180cm in feet and inches"), "5 ft 10.87 in")
  assert.equal(C.evaluate("180cm in feet and inches", env).copy, "5′10.87″")
  assert.equal(result("2 meters in ft and in"), "6 ft 6.74 in")
  assert.equal(result("5 kg in feet and inches"), null, "only lengths")
})

test("lowercase symbols people type, and bytes for lowercase data sizes", () => {
  for (const [q, want] of [
    ["0 c in k", "273.15 K"], ["1 kwh to joules", "3,600,000 J"], ["100 w to hp", "0.1341 hp"], ["1 hp to kw", "0.7457 kW"],
    ["1 atm to pa", "101,325 Pa"], ["1000 kcal to kj", "4,184 kJ"], ["1 cal to j", "4.184 J"], ["2.4 ghz to mhz", "2,400 MHz"],
    ["1 kb to bytes", "1,000 B"], ["1 gb to mb", "1,000 MB"], ["1 gbps to mbps", "1,000 Mbps"], ["8 Mb to kB", "1,000 kB"]
  ]) assert.equal(result(q), want, q)
})

test("ounces to a volume are fluid ounces; CSS absolute lengths are 96 px per inch", () => {
  assert.equal(result("16 oz to ml"), "473.1765 mL")
  assert.equal(result("1in to px"), "96 px")
  assert.equal(result("96px to in"), "1 in")
  assert.equal(result("2.54 cm to px"), "96 px")
  assert.equal(result("12pt to mm"), "4.2333 mm")
})

test("scientific notation shows its value; other bare numbers don't", () => {
  assert.equal(result("1e6"), "1,000,000")
  assert.equal(result("2.5e-3"), "0.0025")
  assert.equal(C.evaluate("1000000", env), null)
})

// ---- fork: money

const money = Object.assign({}, env, {
  homeCurrency: "USD", secondCurrency: "EUR",
  rates: { base: "EUR", date: "2026-10-26", rates: { USD: 1.12, GBP: 0.84, JPY: 177.6, CAD: 1.57, AUD: 1.6, TWD: 36.5, AED: 4.119, RUB: 90.6, BTC: 0.0000137, NGN: 1508 } }
})
const cash = (q, e) => { const r = C.evaluate(q, e || money); return r && r.result }

test("a lone amount of money converts to your currency, or from it to your second", () => {
  assert.equal(cash("€50"), "$56.00")
  assert.equal(cash("100 cad"), "$71.34")
  assert.equal(cash("$100"), "€89.29")
  assert.equal(cash("100 usd"), "€89.29")
  assert.equal(cash("$100", Object.assign({}, money, { homeCurrency: "EUR", secondCurrency: "USD" })), "€89.29")
  assert.equal(cash("€100", Object.assign({}, money, { homeCurrency: "EUR", secondCurrency: "USD" })), "$112.00")
  assert.equal(C.evaluate("$100", Object.assign({}, money, { rates: null })), null, "no rates, no row")
  assert.equal(C.evaluate("usd", money), null, "a bare code is a word, not an amount")
})

test("beside money, pounds are sterling; on their own they're still weight", () => {
  assert.equal(cash("100 dollars in pounds"), "£75.00")
  assert.equal(cash("100 pounds to dollars"), "$133.33")
  assert.equal(cash("150 lbs to kg"), "68.0389 kg")
})

test("Frankfurter's wider list: names, prefixed dollars, new symbols, crypto", () => {
  assert.equal(cash("100 usd to aed"), "367.77 AED")
  assert.equal(cash("50 dirhams to usd"), "$13.60")
  assert.equal(cash("NT$500 to usd"), "$15.34")
  assert.equal(cash("CA$100 to usd"), "$71.34")
  assert.equal(cash("A$100 to usd"), "$70.00")
  assert.equal(cash("₽1000 to usd"), "$12.36")
  assert.equal(cash("1000 naira to usd"), "$0.74")
  assert.equal(cash("1 btc to usd"), "$81,751.82")
  assert.equal(cash("$100 to btc"), "₿0.001223", "crypto keeps significant figures")
  assert.equal(C.evaluate("100 dollars in pounds", money).resultCaption, "British Pound (GBP)")
  assert.equal(C.evaluate("100 usd to aed", money).resultCaption, "United Arab Emirates Dirham (AED)")
})

test("the automatic currency comes from the locale", () => {
  assert.equal(C.localeCurrency("en_US"), "USD")
  assert.equal(C.localeCurrency("en_GB.UTF-8"), "GBP")
  assert.equal(C.localeCurrency("de_DE"), "EUR")
  assert.equal(C.localeCurrency("C"), "")
})

// ---- fork: several targets, metals, shared currency words

const wide = Object.assign({}, money, {
  rates: Object.assign({}, money.rates, { rates: Object.assign({}, money.rates.rates, { MXN: 21, ARS: 1715, KWD: 0.343, KES: 144.6, EGP: 55.5, SEK: 11.2, NOK: 11.8, XAU: 0.0002786, XAG: 0.0234 }) })
})
const w = (q, extra) => { const r = C.evaluate(q, Object.assign({}, wide, extra || {})); return r && [r.result].concat((r.alternatives || []).map((a) => a.result)) }

test("several targets give one answer each; one bad target shows none", () => {
  assert.deepEqual(w("100 usd to eur and gbp"), ["€89.29", "£75.00"])
  assert.deepEqual(w("100 usd in eur, gbp, cad"), ["€89.29", "£75.00", "140.18 CAD"])
  assert.deepEqual(w("$50 to eur & gbp"), ["€44.64", "£37.50"])
  assert.deepEqual(w("5 ft to cm and m"), ["152.4 cm", "1.524 m"])
  assert.deepEqual(w("1 hour in minutes and seconds"), ["60 minutes", "3,600 seconds"])
  assert.equal(w("100 usd to eur and nope"), null)
  assert.deepEqual(w("180cm in feet and inches"), ["5 ft 10.87 in"], "still one target")
  assert.equal(C.evaluate("100 usd to eur and gbp", wide).input, "100 usd to eur and gbp")
})

test("precious metals by weight are troy ounces of XAU/XAG", () => {
  assert.deepEqual(w("1 oz gold to usd"), ["$4,020.10"])
  assert.deepEqual(w("10 g of gold to usd"), ["$1,292.49"])
  assert.deepEqual(w("1 kg silver to usd"), ["$1,538.84"])
  assert.deepEqual(w("1 oz gold"), ["$4,020.10"], "a lone amount converts to your currency")
  assert.equal(C.evaluate("1 oz gold", wide).input, "1 oz gold", "shows what was typed")
  assert.deepEqual(w("2 oz to g"), ["56.699 g"], "without a metal, ounces are ordinary")
})

test("shared currency words follow your currency, else the most common", () => {
  assert.deepEqual(w("100 pesos to usd"), ["$5.33"], "MXN")
  assert.deepEqual(w("100 pesos to usd", { homeCurrency: "ARS" }), ["$0.07"])
  assert.deepEqual(w("100 dinars to usd"), ["$326.53"], "KWD")
  assert.deepEqual(w("1000 shillings to usd"), ["$7.75"], "KES")
  assert.deepEqual(w("100 dollars to eur", { homeCurrency: "CAD" }), ["€63.69"])
  assert.deepEqual(w("100 kroner to usd"), ["$9.49"], "NOK")
  assert.deepEqual(w("100 pounds to dollars", { homeCurrency: "EGP" }), ["$2.02"])
  assert.deepEqual(w("150 pounds to kg"), ["68.0389 kg"], "a weight without money")
})

// ---- fork: configurable lone conversions

test("conversionTargets change what a lone amount converts to", () => {
  const set = (targets) => Object.assign({}, env, { conversionTargets: targets })
  assert.equal(result("5 kg", set({ kg: "g" })), "5,000 g")
  assert.equal(result("16rem", set({ rem: "pt" })), "192 pt")
  assert.equal(C.evaluate("100 f", set({ "°F": "none" })), null, "none switches it off")
  assert.equal(result("100 f to c", set({ "°F": "none" })), "37.7778 °C", "a named target still works")
  assert.equal(result("5 kg", set({ kg: "nope" })), "11.0231 lb", "an unknown unit falls back to the default")
  assert.equal(result("5 kg", set({ kg: "km" })), "11.0231 lb", "so does a different kind")
  assert.equal(result("2 pints", set({ pints: "L" })), "0.9464 L", "units known only by name work too")
})

test("conversionOptions lists each default with its choices and current target", () => {
  const rows = C.conversionOptions({ kg: "g", "°F": "none", rem: "bogus" })
  const row = (sym) => rows.find((r) => r.from === sym)
  assert.ok(rows.length > 40)
  assert.deepEqual([row("kg").target, row("kg").defaultTarget, row("kg").changed, row("kg").kind], ["g", "lb", true, "Weight"])
  assert.deepEqual([row("°F").target, row("°F").changed], ["none", true])
  assert.deepEqual([row("rem").target, row("rem").changed], ["px", false], "an invalid choice shows the default")
  assert.ok(row("kg").choices.some((c) => c.value === "oz") && !row("kg").choices.some((c) => c.value === "kg"), "same kind, not itself")
  assert.deepEqual(row("°C").choices.map((c) => c.value).sort(), ["K", "°F"])
})

// ---- fork: measurement systems

test("the measurement system picks the defaults and what imperial words mean", () => {
  const as = (system, q) => { const r = C.evaluate(q, Object.assign({}, env, { measurementSystem: system })); return r && r.result }
  assert.equal(as("us", "70 kg"), "154.3236 lb")
  assert.equal(as("uk", "70 kg"), "11.0231 st", "UK body weight in stone")
  assert.equal(as("us", "300 k"), "80.33 °F")
  assert.equal(as("metric", "300 k"), "26.85 °C")
  assert.equal(as("us", "10 m/s"), "22.3694 mph")
  assert.equal(as("metric", "10 m/s"), "36 km/h")
  assert.equal(as("us", "180 cm"), "5 ft 10.87 in", "US and UK heights in feet and inches")
  assert.equal(as("uk", "1.8 m"), "5 ft 10.87 in")
  assert.equal(as("us", "30 cm"), "11.81 in", "no 0 ft")
  assert.equal(as("metric", "180 cm"), "70.8661 in")
  assert.equal(as("us", "180 cm to in"), "70.8661 in", "a named target wins")
  assert.equal(as("uk", "1 pint to ml"), "568.2613 mL", "a UK pint is imperial")
  assert.equal(as("us", "1 pint to ml"), "473.1765 mL")
  assert.equal(as("uk", "1 gal to L"), "4.5461 L")
  assert.equal(as("uk", "1 us gallon to L"), "3.7854 L", "unless it says US")
  assert.equal(as("uk", "2 L"), "3.5195 imp pt")
  assert.equal(as(undefined, "70 kg"), "154.3236 lb", "metric when unset")
})

test("the system comes from the locale; feet and inches is a choice for lengths", () => {
  assert.equal(C.measurementSystem("en_US"), "us")
  assert.equal(C.measurementSystem("en_GB.UTF-8"), "uk")
  assert.equal(C.measurementSystem("de_DE"), "metric")
  assert.equal(C.measurementSystem("C"), "metric")
  const cm = C.conversionOptions({}, "us").find((r) => r.from === "cm")
  assert.equal(cm.target, "ft+in")
  assert.equal(C.conversionOptions({}, "metric").find((r) => r.from === "cm").target, "in")
  assert.equal(cm.choices.find((c) => c.value === "ft+in").label, "Feet and inches (5 ft 10 in)")
  const m = (q) => { const r = C.evaluate(q, Object.assign({}, env, { conversionTargets: { cm: "ft+in" } })); return r && r.result }
  assert.equal(m("180 cm"), "5 ft 10.87 in", "a metric user can pick it too")
})
