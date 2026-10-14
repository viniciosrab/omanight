// Night light model: pure schedule, override, and sun math shared by the
// service and the panel. No I/O, so it runs under node for the unit tests
// (tests/model.test.js) as well as inside QML.
//
// Times of day are minutes since local midnight (fractions allowed). Instants
// are millisecond timestamps. Temperatures are kelvin; `null` in an override
// means "off", which the screen shows as DAY_TEMPERATURE.

var MIN_TEMPERATURE = 1000
var MAX_TEMPERATURE = 6500
var DAY_TEMPERATURE = 6500
// Below this the light counts as on. Matches the stock service and
// bin/omarchy-toggle-nightlight so every indicator agrees.
var IDENTITY_TEMPERATURE = 6000
var MAX_FADE_MINUTES = 240

var MODES = ["sun", "fixed", "manual"]

var PRESETS = [
  { value: "day", label: "Day", temperature: 6500 },
  { value: "evening", label: "Evening", temperature: 4000 },
  { value: "night", label: "Night", temperature: 3400 },
  { value: "candle", label: "Candle", temperature: 1900 }
]

var HOLDS = [
  { value: "next", label: "Next change" },
  { value: "1h", label: "1 hour" },
  { value: "morning", label: "Morning" }
]

function defaultState() {
  return {
    version: 1,
    mode: "sun",
    eveningTemperature: 3400,
    lateTemperature: 2700,
    lateAfterMinutes: 180,
    fadeMinutes: 45,
    onTime: "20:00",
    offTime: "07:00",
    manualTemperature: 4000,
    defaultHold: "next",
    override: null,
    latitude: null,
    longitude: null,
    locationName: ""
  }
}

// ---- Small helpers -----------------------------------------------------

function finiteNumber(value) {
  if (value === null || value === undefined || value === "" || typeof value === "boolean") return null
  var n = Number(value)
  return isFinite(n) ? n : null
}

function clampTemperature(value, fallback) {
  var n = finiteNumber(value)
  if (n === null) return fallback
  return Math.max(MIN_TEMPERATURE, Math.min(MAX_TEMPERATURE, Math.round(n)))
}

function clampInt(value, low, high, fallback) {
  var n = finiteNumber(value)
  if (n === null) return fallback
  return Math.max(low, Math.min(high, Math.round(n)))
}

function isNight(temperature) {
  return temperature !== null && temperature !== undefined && temperature < IDENTITY_TEMPERATURE
}

function wrapMinutes(minutes) {
  return ((minutes % 1440) + 1440) % 1440
}

function parseHHMM(text) {
  var m = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(String(text === undefined || text === null ? "" : text))
  if (!m) return null
  var h = Number(m[1]), mm = Number(m[2])
  if (h > 23 || mm > 59) return null
  return h * 60 + mm
}

function formatHHMM(minutes) {
  var m = Math.round(wrapMinutes(Math.round(minutes)))
  var h = Math.floor(m / 60) % 24
  var mm = m % 60
  return (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm
}

function minuteOfDay(date) {
  return date.getHours() * 60 + date.getMinutes() + date.getSeconds() / 60 + date.getMilliseconds() / 60000
}

// The next instant strictly after `now` whose local clock reads `minutes`.
function nextOccurrence(minutes, now) {
  var whole = Math.round(wrapMinutes(minutes))
  for (var day = 0; day <= 2; day++) {
    var at = new Date(now.getFullYear(), now.getMonth(), now.getDate() + day, Math.floor(whole / 60), whole % 60, 0, 0)
    if (at.getTime() > now.getTime()) return at
  }
  return null
}

// Interpolate in mireds (1e6 / K): equal mired steps are equal perceived
// steps, so a fade does not crawl at the warm end and lurch at the cool end.
function miredMix(fromK, toK, t) {
  t = Math.max(0, Math.min(1, Number(t) || 0))
  var a = 1000000 / fromK
  var b = 1000000 / toK
  return Math.round(1000000 / (a + (b - a) * t))
}

// ---- Sun ------------------------------------------------------------------

function hasCoordinates(lat, lon) {
  var a = finiteNumber(lat), b = finiteNumber(lon)
  return a !== null && b !== null && a >= -90 && a <= 90 && b >= -180 && b <= 180
}

// NOAA general solar position equations. Returns local minutes for sunrise
// and sunset on `date`'s calendar day, or `polar: "day" | "night"` when the
// sun does not cross the horizon there.
function sunTimes(lat, lon, date) {
  if (!hasCoordinates(lat, lon)) return { sunrise: null, sunset: null, polar: null }
  date = date || new Date()
  var start = Date.UTC(date.getFullYear(), 0, 1)
  var n = Math.floor((Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) - start) / 86400000) + 1
  var g = 2 * Math.PI / 365 * (n - 1)
  var eqtime = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
    - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g))
  var decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g)
    - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g)
    - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g)
  var phi = Number(lat) * Math.PI / 180
  var cosHa = Math.cos(90.833 * Math.PI / 180) / (Math.cos(phi) * Math.cos(decl)) - Math.tan(phi) * Math.tan(decl)
  if (cosHa > 1) return { sunrise: null, sunset: null, polar: "night" }
  if (cosHa < -1) return { sunrise: null, sunset: null, polar: "day" }
  var ha = Math.acos(cosHa) * 180 / Math.PI
  var noon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12, 0, 0)
  var offset = noon.getTimezoneOffset()
  return {
    sunrise: Math.round(wrapMinutes(720 - 4 * (Number(lon) + ha) - eqtime - offset)),
    sunset: Math.round(wrapMinutes(720 - 4 * (Number(lon) - ha) - eqtime - offset)),
    polar: null
  }
}

// ---- Schedule -------------------------------------------------------------

function usableSun(sun) {
  return !!sun && sun.sunrise !== null && sun.sunrise !== undefined
    && sun.sunset !== null && sun.sunset !== undefined
}

// The night as start/end minutes of day. Sun mode without usable sun times
// (no location yet, polar day or night) falls back to the fixed times.
function nightWindow(state, sun) {
  if (state.mode === "manual") return null
  if (state.mode === "sun" && usableSun(sun))
    return { start: sun.sunset, end: sun.sunrise, source: "sun" }
  var start = parseHHMM(state.onTime), end = parseHHMM(state.offTime)
  if (start === null || end === null) return null
  return { start: start, end: end, source: "fixed" }
}

// Everything the schedule needs, in minutes since night start: the night
// length, when the late stage begins (0 = none), and each fade's length,
// shortened so no two fades overlap.
function nightPlan(state, sun) {
  var w = nightWindow(state, sun)
  if (!w) return null
  var len = wrapMinutes(w.end - w.start)
  if (len === 0) return null
  var fade = clampInt(state.fadeMinutes, 0, MAX_FADE_MINUTES, 0)
  var late = state.lateAfterMinutes > 0 && state.lateAfterMinutes < len ? state.lateAfterMinutes : 0
  var fadeIn, fadeLate = 0, fadeOut
  if (late) {
    fadeIn = Math.min(fade, late)
    fadeLate = Math.min(fade, Math.floor((len - late) / 2))
    fadeOut = fadeLate
  } else {
    fadeIn = Math.min(fade, Math.floor(len / 2))
    fadeOut = fadeIn
  }
  return {
    window: w, start: w.start, end: w.end, length: len, late: late,
    fadeIn: fadeIn, fadeLate: fadeLate, fadeOut: fadeOut,
    evening: clampTemperature(state.eveningTemperature, 3400),
    lateTemperature: clampTemperature(state.lateTemperature, 2700)
  }
}

function elapsedInNight(plan, date) {
  return wrapMinutes(minuteOfDay(date) - plan.start)
}

function scheduledTemperature(state, sun, date) {
  if (state.mode === "manual") return clampTemperature(state.manualTemperature, 4000)
  var p = nightPlan(state, sun)
  if (!p) return DAY_TEMPERATURE
  var e = elapsedInNight(p, date)
  if (e >= p.length) return DAY_TEMPERATURE
  var deep = p.late ? p.lateTemperature : p.evening
  var outStart = p.length - p.fadeOut
  if (p.fadeOut > 0 && e >= outStart) return miredMix(deep, DAY_TEMPERATURE, (e - outStart) / p.fadeOut)
  if (p.late && e >= p.late) {
    if (p.fadeLate > 0 && e < p.late + p.fadeLate) return miredMix(p.evening, p.lateTemperature, (e - p.late) / p.fadeLate)
    return p.lateTemperature
  }
  if (p.fadeIn > 0 && e < p.fadeIn) return miredMix(DAY_TEMPERATURE, p.evening, e / p.fadeIn)
  return p.evening
}

// The night's changes for the timeline, in order from night start. Each
// change begins at `minute` and settles `fadeMinutes` later.
function scheduleEvents(state, sun) {
  var p = nightPlan(state, sun)
  if (!p) return []
  var out = [{ minute: p.start, kind: "evening", temperature: p.evening, fadeMinutes: p.fadeIn, fromTemperature: DAY_TEMPERATURE }]
  if (p.late)
    out.push({ minute: wrapMinutes(p.start + p.late), kind: "late", temperature: p.lateTemperature, fadeMinutes: p.fadeLate, fromTemperature: p.evening })
  out.push({ minute: wrapMinutes(p.end - p.fadeOut), kind: "day", temperature: DAY_TEMPERATURE, fadeMinutes: p.fadeOut, fromTemperature: p.late ? p.lateTemperature : p.evening })
  for (var i = 0; i < out.length; i++) out[i].endMinute = wrapMinutes(out[i].minute + out[i].fadeMinutes)
  return out
}

function nextChange(state, sun, now) {
  var events = scheduleEvents(state, sun)
  var best = null
  for (var i = 0; i < events.length; i++) {
    var at = nextOccurrence(events[i].minute, now)
    if (at && (!best || at.getTime() < best.getTime())) best = at
  }
  return best
}

function nextMorning(state, sun, now) {
  var p = nightPlan(state, sun)
  return p ? nextOccurrence(p.end, now) : null
}

function inTransition(state, sun, now) {
  if (overrideActive(state, now) || state.mode === "manual") return false
  var p = nightPlan(state, sun)
  if (!p) return false
  var e = elapsedInNight(p, now)
  if (e >= p.length) return false
  if (p.fadeIn > 0 && e < p.fadeIn) return true
  if (p.late && p.fadeLate > 0 && e >= p.late && e < p.late + p.fadeLate) return true
  return p.fadeOut > 0 && e >= p.length - p.fadeOut
}

// ---- Overrides --------------------------------------------------------------

// When an override taken now with `hold` ends: a timestamp, or null for
// "until resumed". Throws on a hold it does not understand.
function holdUntil(hold, state, sun, now) {
  var h = String(hold || "")
  if (h === "forever") return null
  if (h === "next") {
    var next = nextChange(state, sun, now)
    return next ? next.getTime() : null
  }
  if (h === "morning") {
    var morning = nextMorning(state, sun, now)
    return morning ? morning.getTime() : null
  }
  var span = /^(\d+)([mh])$/.exec(h)
  if (span) return now.getTime() + Number(span[1]) * (span[2] === "h" ? 3600000 : 60000)
  var clock = parseHHMM(h)
  if (clock !== null) return nextOccurrence(clock, now).getTime()
  throw new Error("bad hold: " + h)
}

function overrideActive(state, now) {
  var o = state.override
  if (!o) return false
  return o.until === null || o.until === undefined || now.getTime() < o.until
}

function targetTemperature(state, sun, now) {
  if (overrideActive(state, now)) {
    var t = state.override.temperature
    return { temperature: t === null || t === undefined ? DAY_TEMPERATURE : clampTemperature(t, DAY_TEMPERATURE), source: "override" }
  }
  return { temperature: scheduledTemperature(state, sun, now), source: state.mode === "manual" ? "manual" : "schedule" }
}

function makeOverride(temperature, hold, state, sun, now) {
  return {
    temperature: temperature === null || temperature === undefined ? null : clampTemperature(temperature, DAY_TEMPERATURE),
    hold: hold,
    until: holdUntil(hold, state, sun, now)
  }
}

// The override for switching the light on or off by hand: null (clear it)
// when the schedule already agrees, else held until the next change.
function toggleOverride(state, sun, now, on) {
  var scheduledOn = isNight(scheduledTemperature(state, sun, now))
  if (!!on === scheduledOn) return null
  if (!on) return makeOverride(null, "next", state, sun, now)
  var warm = state.mode === "manual" && isNight(state.manualTemperature)
    ? state.manualTemperature : state.eveningTemperature
  return makeOverride(warm, "next", state, sun, now)
}

// Something outside the service (the `omarchy toggle nightlight` keybinding)
// set hyprsunset to `observed`. Returns the override that keeps that choice
// until the next change, or undefined when nothing needs to change.
function adoptExternal(state, sun, now, observed) {
  if (observed === null || observed === undefined) return undefined
  var target = targetTemperature(state, sun, now).temperature
  if (Math.round(observed) === target) return undefined
  return makeOverride(observed >= IDENTITY_TEMPERATURE ? null : observed, "next", state, sun, now)
}

// ---- Presentation -------------------------------------------------------------

function warmthName(temperature) {
  var t = finiteNumber(temperature)
  if (t === null) return "Unknown"
  if (t >= 6000) return "Day"
  if (t >= 4500) return "Neutral"
  if (t >= 3700) return "Evening"
  if (t >= 3000) return "Night"
  if (t >= 2300) return "Tungsten"
  if (t >= 1600) return "Candle"
  return "Ember"
}

function presetForTemperature(temperature) {
  for (var i = 0; i < PRESETS.length; i++)
    if (PRESETS[i].temperature === Math.round(Number(temperature))) return PRESETS[i].value
  return ""
}

function presetTemperature(name) {
  for (var i = 0; i < PRESETS.length; i++)
    if (PRESETS[i].value === name) return PRESETS[i].temperature
  return null
}

function clockOf(ms) {
  var d = new Date(ms)
  return formatHHMM(d.getHours() * 60 + d.getMinutes())
}

function statusText(state, sun, now, hasLocation) {
  if (overrideActive(state, now)) {
    var o = state.override
    var head = o.temperature === null || o.temperature === undefined ? "Off" : "Held at " + o.temperature + "K"
    return o.until === null || o.until === undefined ? head : head + " until " + clockOf(o.until)
  }
  if (state.mode === "manual") return "Manual · " + warmthName(state.manualTemperature)
  var p = nightPlan(state, sun)
  if (!p) return "No night in this schedule"
  var range = formatHHMM(parseHHMM(state.onTime)) + "–" + formatHHMM(parseHHMM(state.offTime))
  if (state.mode === "sun" && p.window.source === "fixed") {
    if (sun && sun.polar === "day") return "Polar day · using " + range
    if (sun && sun.polar === "night") return "Polar night · using " + range
    if (!hasLocation) return "No location · using " + range
  }
  var e = elapsedInNight(p, now)
  var bySun = p.window.source === "sun"
  if (e >= p.length)
    return (bySun ? "Sunset " : "On at ") + formatHHMM(p.start) + " → " + p.evening + "K"
  if (p.fadeOut > 0 && e >= p.length - p.fadeOut) return "Cooling until " + formatHHMM(p.end)
  if (p.fadeIn > 0 && e < p.fadeIn) return "Warming until " + formatHHMM(p.start + p.fadeIn)
  if (p.late && p.fadeLate > 0 && e >= p.late && e < p.late + p.fadeLate)
    return "Warming until " + formatHHMM(p.start + p.late + p.fadeLate)
  if (p.late && e < p.late) return "Late " + p.lateTemperature + "K at " + formatHHMM(p.start + p.late)
  return bySun ? "Sunrise " + formatHHMM(p.end) + " → " + DAY_TEMPERATURE + "K" : "Off at " + formatHHMM(p.end)
}

// Blackbody approximation (Tanner Helland's fit) for swatches and gradients.
// Channels are 0..1 so QML can hand them straight to Qt.rgba.
function kelvinColor(kelvin) {
  var t = clampTemperature(kelvin, DAY_TEMPERATURE) / 100
  var r, g, b
  if (t <= 66) {
    r = 255
    g = 99.4708025861 * Math.log(t) - 161.1195681661
    b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307
  } else {
    r = 329.698727446 * Math.pow(t - 60, -0.1332047592)
    g = 288.1221695283 * Math.pow(t - 60, -0.0755148492)
    b = 255
  }
  function c(v) { return Math.max(0, Math.min(255, v)) / 255 }
  return { r: c(r), g: c(g), b: c(b) }
}

// ---- Parsing ----------------------------------------------------------------

// `hyprctl hyprsunset temperature` prints just the number; anything else
// (an error mentioning a socket path, say) is not a reading.
function temperatureFromOutput(output) {
  var m = /^\s*(\d+)\s*$/.exec(String(output === undefined || output === null ? "" : output).split("\n")[0])
  return m ? Number(m[1]) : null
}

function parseOverride(o) {
  if (!o || typeof o !== "object") return null
  var temperature = null
  if (o.temperature !== null) {
    if (finiteNumber(o.temperature) === null) return null
    temperature = clampTemperature(o.temperature, DAY_TEMPERATURE)
  }
  var until = null
  if (o.until !== null && o.until !== undefined) {
    until = finiteNumber(o.until)
    if (until === null) return null
  }
  return { temperature: temperature, hold: typeof o.hold === "string" ? o.hold : "next", until: until }
}

function parseState(raw) {
  var state = defaultState()
  if (!raw) return state
  var p
  try { p = JSON.parse(String(raw)) } catch (error) { return state }
  if (!p || typeof p !== "object" || Array.isArray(p)) return state
  if (MODES.indexOf(p.mode) !== -1) state.mode = p.mode
  state.eveningTemperature = clampTemperature(p.eveningTemperature, state.eveningTemperature)
  state.lateTemperature = clampTemperature(p.lateTemperature, state.lateTemperature)
  state.manualTemperature = clampTemperature(p.manualTemperature, state.manualTemperature)
  state.lateAfterMinutes = clampInt(p.lateAfterMinutes, 0, 1439, state.lateAfterMinutes)
  state.fadeMinutes = clampInt(p.fadeMinutes, 0, MAX_FADE_MINUTES, state.fadeMinutes)
  if (parseHHMM(p.onTime) !== null) state.onTime = formatHHMM(parseHHMM(p.onTime))
  if (parseHHMM(p.offTime) !== null) state.offTime = formatHHMM(parseHHMM(p.offTime))
  for (var i = 0; i < HOLDS.length; i++) if (HOLDS[i].value === p.defaultHold) state.defaultHold = p.defaultHold
  state.override = parseOverride(p.override)
  if (hasCoordinates(p.latitude, p.longitude)) {
    state.latitude = Number(p.latitude)
    state.longitude = Number(p.longitude)
  }
  if (typeof p.locationName === "string") state.locationName = p.locationName
  return state
}

function serializeState(state) {
  return JSON.stringify(parseState(JSON.stringify(state)), null, 2) + "\n"
}

function parseWeatherLocation(raw) {
  try {
    var p = JSON.parse(String(raw))
    var ok = hasCoordinates(p.latitude, p.longitude)
    return {
      name: typeof p.name === "string" ? p.name : "",
      latitude: ok ? Number(p.latitude) : null,
      longitude: ok ? Number(p.longitude) : null
    }
  } catch (error) {
    return { name: "", latitude: null, longitude: null }
  }
}

function parseGeocode(raw) {
  try {
    var first = JSON.parse(String(raw)).results[0]
    if (!first || !hasCoordinates(first.latitude, first.longitude)) return null
    var parts = []
    if (first.name) parts.push(String(first.name))
    if (first.admin1) parts.push(String(first.admin1))
    return { latitude: Number(first.latitude), longitude: Number(first.longitude), name: parts.join(", ") }
  } catch (error) {
    return null
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    MIN_TEMPERATURE: MIN_TEMPERATURE, MAX_TEMPERATURE: MAX_TEMPERATURE, DAY_TEMPERATURE: DAY_TEMPERATURE,
    IDENTITY_TEMPERATURE: IDENTITY_TEMPERATURE, MAX_FADE_MINUTES: MAX_FADE_MINUTES,
    MODES: MODES, PRESETS: PRESETS, HOLDS: HOLDS,
    defaultState: defaultState, clampTemperature: clampTemperature, isNight: isNight,
    parseHHMM: parseHHMM, formatHHMM: formatHHMM, minuteOfDay: minuteOfDay, nextOccurrence: nextOccurrence,
    miredMix: miredMix, hasCoordinates: hasCoordinates, sunTimes: sunTimes,
    nightWindow: nightWindow, nightPlan: nightPlan, scheduledTemperature: scheduledTemperature,
    scheduleEvents: scheduleEvents, nextChange: nextChange, nextMorning: nextMorning, inTransition: inTransition,
    holdUntil: holdUntil, overrideActive: overrideActive, targetTemperature: targetTemperature,
    makeOverride: makeOverride, toggleOverride: toggleOverride, adoptExternal: adoptExternal,
    warmthName: warmthName, presetForTemperature: presetForTemperature, presetTemperature: presetTemperature,
    statusText: statusText, kelvinColor: kelvinColor, temperatureFromOutput: temperatureFromOutput,
    parseState: parseState, serializeState: serializeState,
    parseWeatherLocation: parseWeatherLocation, parseGeocode: parseGeocode
  }
}
