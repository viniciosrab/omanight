// Unit tests for the pure night light model. Run with: node --test tests/
process.env.TZ = "Europe/London"

const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../Model.js")

function at(y, mo, d, h, mi) { return new Date(y, mo - 1, d, h, mi, 0, 0) }
function fixed(overrides) {
  return Object.assign(M.defaultState(), { mode: "fixed", onTime: "20:00", offTime: "07:00", fadeMinutes: 0, lateAfterMinutes: 180 }, overrides || {})
}
const NO_SUN = { sunrise: null, sunset: null, polar: null }
function near(actual, expected, tolerance, message) {
  assert.ok(Math.abs(actual - expected) <= tolerance, (message || "") + " expected " + expected + "±" + tolerance + ", got " + actual)
}

test("mired mix interpolates perceptually, not linearly in kelvin", () => {
  assert.equal(M.miredMix(6500, 3400, 0), 6500)
  assert.equal(M.miredMix(6500, 3400, 1), 3400)
  assert.equal(M.miredMix(6500, 3400, 0.5), 4465)
  assert.equal(M.miredMix(6500, 3400, 2), 3400, "t is clamped")
})

test("clamps temperatures into 1000..6500 with fallback for junk", () => {
  assert.equal(M.clampTemperature(500, 4000), 1000)
  assert.equal(M.clampTemperature(9000, 4000), 6500)
  assert.equal(M.clampTemperature("abc", 4000), 4000)
  assert.equal(M.clampTemperature(3456.6, 4000), 3457)
})

test("parses and formats HH:MM", () => {
  assert.equal(M.parseHHMM("07:05"), 425)
  assert.equal(M.parseHHMM("7:05"), 425)
  assert.equal(M.parseHHMM("24:00"), null)
  assert.equal(M.parseHHMM("12:60"), null)
  assert.equal(M.parseHHMM(""), null)
  assert.equal(M.formatHHMM(425), "07:05")
  assert.equal(M.formatHHMM(1440 + 5), "00:05")
  assert.equal(M.formatHHMM(-5), "23:55")
})

test("sun times match NOAA within a few minutes (London, summer solstice)", () => {
  const sun = M.sunTimes(51.5074, -0.1278, at(2024, 6, 21, 12, 0))
  near(sun.sunrise, 4 * 60 + 43, 3, "sunrise")
  near(sun.sunset, 21 * 60 + 21, 3, "sunset")
  assert.equal(sun.polar, null)
})

test("sun times report polar day and polar night", () => {
  const summer = M.sunTimes(69.65, 18.96, at(2024, 6, 21, 12, 0))
  assert.equal(summer.polar, "day")
  assert.equal(summer.sunrise, null)
  const winter = M.sunTimes(69.65, 18.96, at(2024, 12, 21, 12, 0))
  assert.equal(winter.polar, "night")
  assert.equal(M.sunTimes(null, 10, new Date()).sunrise, null)
})

test("fixed schedule without fade steps evening, late, and day", () => {
  const s = fixed()
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 19, 59)), 6500)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 20, 0)), 3400)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 22, 59)), 3400)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 23, 0)), 2700)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 6, 59)), 2700)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 7, 0)), 6500)
})

test("late stage is skipped when disabled or past the night end", () => {
  assert.equal(M.scheduledTemperature(fixed({ lateAfterMinutes: 0 }), NO_SUN, at(2026, 1, 2, 3, 0)), 3400)
  assert.equal(M.scheduledTemperature(fixed({ lateAfterMinutes: 700 }), NO_SUN, at(2026, 1, 2, 6, 0)), 3400)
})

test("fades start at the evening event and end at the night end", () => {
  const s = fixed({ fadeMinutes: 60, lateAfterMinutes: 0 })
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 20, 0)), 6500)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 20, 30)), 4465)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 21, 0)), 3400)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 6, 0)), 3400)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 6, 30)), 4465)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 7, 0)), 6500)
})

test("late fade eases from evening to late", () => {
  const s = fixed({ fadeMinutes: 60, lateAfterMinutes: 180 })
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 23, 0)), 3400)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 23, 30)), M.miredMix(3400, 2700, 0.5))
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 0, 0)), 2700)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 2, 6, 30)), M.miredMix(2700, 6500, 0.5))
})

test("fades are shortened so they never overlap", () => {
  const s = fixed({ onTime: "20:00", offTime: "21:00", fadeMinutes: 60, lateAfterMinutes: 0 })
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 20, 30)), 3400)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 20, 45)), M.miredMix(3400, 6500, 0.5))
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 21, 0)), 6500)
})

test("sun mode uses sunset and sunrise, and falls back to fixed times without sun", () => {
  const s = Object.assign(M.defaultState(), { mode: "sun", fadeMinutes: 0, lateAfterMinutes: 0, onTime: "20:00", offTime: "07:00" })
  const sun = { sunrise: 6 * 60 + 30, sunset: 18 * 60 + 15, polar: null }
  assert.equal(M.scheduledTemperature(s, sun, at(2026, 1, 1, 18, 14)), 6500)
  assert.equal(M.scheduledTemperature(s, sun, at(2026, 1, 1, 18, 15)), 3400)
  assert.equal(M.scheduledTemperature(s, sun, at(2026, 1, 2, 6, 30)), 6500)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 19, 0)), 6500)
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 20, 0)), 3400)
  assert.equal(M.nightWindow(s, NO_SUN).source, "fixed")
  assert.equal(M.nightWindow(s, sun).source, "sun")
})

test("manual mode holds the manual temperature all day", () => {
  const s = Object.assign(M.defaultState(), { mode: "manual", manualTemperature: 2900 })
  assert.equal(M.scheduledTemperature(s, NO_SUN, at(2026, 1, 1, 12, 0)), 2900)
  assert.equal(M.nextChange(s, NO_SUN, at(2026, 1, 1, 12, 0)), null)
})

test("next change and next morning cross midnight", () => {
  const s = fixed({ fadeMinutes: 30 })
  assert.equal(M.nextChange(s, NO_SUN, at(2026, 1, 1, 12, 0)).getTime(), at(2026, 1, 1, 20, 0).getTime())
  assert.equal(M.nextChange(s, NO_SUN, at(2026, 1, 1, 21, 0)).getTime(), at(2026, 1, 1, 23, 0).getTime())
  assert.equal(M.nextChange(s, NO_SUN, at(2026, 1, 2, 1, 0)).getTime(), at(2026, 1, 2, 6, 30).getTime(), "morning fade start")
  assert.equal(M.nextMorning(s, NO_SUN, at(2026, 1, 1, 21, 0)).getTime(), at(2026, 1, 2, 7, 0).getTime())
  assert.equal(M.nextMorning(s, NO_SUN, at(2026, 1, 2, 8, 0)).getTime(), at(2026, 1, 3, 7, 0).getTime())
})

test("hold deadlines", () => {
  const s = fixed()
  const now = at(2026, 1, 1, 21, 0)
  assert.equal(M.holdUntil("next", s, NO_SUN, now), at(2026, 1, 1, 23, 0).getTime())
  assert.equal(M.holdUntil("morning", s, NO_SUN, now), at(2026, 1, 2, 7, 0).getTime())
  assert.equal(M.holdUntil("1h", s, NO_SUN, now), at(2026, 1, 1, 22, 0).getTime())
  assert.equal(M.holdUntil("30m", s, NO_SUN, now), at(2026, 1, 1, 21, 30).getTime())
  assert.equal(M.holdUntil("20:30", s, NO_SUN, now), at(2026, 1, 2, 20, 30).getTime())
  assert.equal(M.holdUntil("forever", s, NO_SUN, now), null)
  assert.equal(M.holdUntil("next", Object.assign(M.defaultState(), { mode: "manual" }), NO_SUN, now), null)
  assert.throws(() => M.holdUntil("soon", s, NO_SUN, now))
})

test("an override wins until it expires; off means daylight", () => {
  const now = at(2026, 1, 1, 21, 0)
  const s = fixed({ override: { temperature: 1900, hold: "1h", until: at(2026, 1, 1, 22, 0).getTime() } })
  assert.deepEqual(M.targetTemperature(s, NO_SUN, now), { temperature: 1900, source: "override" })
  assert.deepEqual(M.targetTemperature(s, NO_SUN, at(2026, 1, 1, 22, 0)), { temperature: 3400, source: "schedule" })
  const off = fixed({ override: { temperature: null, hold: "forever", until: null } })
  assert.deepEqual(M.targetTemperature(off, NO_SUN, now), { temperature: 6500, source: "override" })
  assert.equal(M.overrideActive(off, now), true)
  assert.equal(M.overrideActive(s, at(2026, 1, 1, 23, 0)), false)
})

test("toggle sets an override until the next change, or clears it when it matches the schedule", () => {
  const night = at(2026, 1, 1, 21, 0)
  const off = M.toggleOverride(fixed(), NO_SUN, night, false)
  assert.deepEqual(off, { temperature: null, hold: "next", until: at(2026, 1, 1, 23, 0).getTime() })
  assert.equal(M.toggleOverride(fixed({ override: off }), NO_SUN, night, true), null)
  const day = at(2026, 1, 1, 12, 0)
  assert.deepEqual(M.toggleOverride(fixed(), NO_SUN, day, true), { temperature: 3400, hold: "next", until: at(2026, 1, 1, 20, 0).getTime() })
  assert.equal(M.toggleOverride(fixed(), NO_SUN, day, false), null)
})

test("external changes become overrides; matching readings change nothing", () => {
  const night = at(2026, 1, 1, 21, 0)
  assert.equal(M.adoptExternal(fixed(), NO_SUN, night, 3400), undefined)
  assert.deepEqual(M.adoptExternal(fixed(), NO_SUN, night, 6500), { temperature: null, hold: "next", until: at(2026, 1, 1, 23, 0).getTime() })
  assert.deepEqual(M.adoptExternal(fixed(), NO_SUN, at(2026, 1, 1, 12, 0), 4000), { temperature: 4000, hold: "next", until: at(2026, 1, 1, 20, 0).getTime() })
  assert.equal(M.adoptExternal(fixed(), NO_SUN, night, null), undefined)
})

test("state parsing validates and round-trips", () => {
  assert.deepEqual(M.parseState(""), M.defaultState())
  assert.deepEqual(M.parseState("{not json"), M.defaultState())
  const parsed = M.parseState(JSON.stringify({
    mode: "bogus", eveningTemperature: 99999, lateTemperature: "x", lateAfterMinutes: -4,
    fadeMinutes: 9999, onTime: "25:00", offTime: "06:15", defaultHold: "1h",
    override: { temperature: 2000, hold: "1h", until: 123 }, latitude: 91, longitude: 10, locationName: 7
  }))
  assert.equal(parsed.mode, "sun")
  assert.equal(parsed.eveningTemperature, 6500)
  assert.equal(parsed.lateTemperature, M.defaultState().lateTemperature)
  assert.equal(parsed.lateAfterMinutes, 0)
  assert.equal(parsed.fadeMinutes, 240)
  assert.equal(parsed.onTime, M.defaultState().onTime)
  assert.equal(parsed.offTime, "06:15")
  assert.equal(parsed.defaultHold, "1h")
  assert.deepEqual(parsed.override, { temperature: 2000, hold: "1h", until: 123 })
  assert.equal(parsed.latitude, null, "latitude out of range is dropped")
  assert.equal(parsed.locationName, "")
  const bad = M.parseState(JSON.stringify({ override: { temperature: "warm" } }))
  assert.equal(bad.override, null)
  const s = fixed({ override: { temperature: null, hold: "next", until: 5 } })
  assert.deepEqual(M.parseState(M.serializeState(s)), s)
})

test("schedule events describe the night for the timeline", () => {
  const events = M.scheduleEvents(fixed({ fadeMinutes: 30 }), NO_SUN)
  assert.deepEqual(events.map(e => [M.formatHHMM(e.minute), e.kind, e.temperature, e.fadeMinutes]), [
    ["20:00", "evening", 3400, 30],
    ["23:00", "late", 2700, 30],
    ["06:30", "day", 6500, 30]
  ])
  assert.deepEqual(M.scheduleEvents(Object.assign(M.defaultState(), { mode: "manual" }), NO_SUN), [])
})

test("status text explains what happens next", () => {
  const s = fixed({ fadeMinutes: 60, lateAfterMinutes: 0 })
  assert.equal(M.statusText(s, NO_SUN, at(2026, 1, 1, 12, 0), true), "On at 20:00 → 3400K")
  assert.equal(M.statusText(s, NO_SUN, at(2026, 1, 1, 20, 30), true), "Warming until 21:00")
  assert.equal(M.statusText(s, NO_SUN, at(2026, 1, 1, 22, 0), true), "Off at 07:00")
  assert.equal(M.statusText(s, NO_SUN, at(2026, 1, 2, 6, 30), true), "Cooling until 07:00")
  const held = fixed({ override: { temperature: null, hold: "next", until: at(2026, 1, 1, 23, 0).getTime() } })
  assert.equal(M.statusText(held, NO_SUN, at(2026, 1, 1, 21, 0), true), "Off until 23:00")
  const kept = fixed({ override: { temperature: 1900, hold: "forever", until: null } })
  assert.equal(M.statusText(kept, NO_SUN, at(2026, 1, 1, 21, 0), true), "Held at 1900K")
  const sun = Object.assign(M.defaultState(), { mode: "sun", lateAfterMinutes: 0, fadeMinutes: 0 })
  assert.equal(M.statusText(sun, { sunrise: 390, sunset: 1095, polar: null }, at(2026, 1, 1, 12, 0), true), "Sunset 18:15 → 3400K")
  assert.equal(M.statusText(sun, { sunrise: 390, sunset: 1095, polar: null }, at(2026, 1, 1, 22, 0), true), "Sunrise 06:30 → 6500K")
  assert.equal(M.statusText(sun, NO_SUN, at(2026, 1, 1, 12, 0), false), "No location · using 20:00–07:00")
  assert.equal(M.statusText(Object.assign(M.defaultState(), { mode: "manual", manualTemperature: 3400 }), NO_SUN, at(2026, 1, 1, 12, 0), true), "Manual · Night")
})

test("transition detection drives the fast tick", () => {
  const s = fixed({ fadeMinutes: 60, lateAfterMinutes: 0 })
  assert.equal(M.inTransition(s, NO_SUN, at(2026, 1, 1, 20, 30)), true)
  assert.equal(M.inTransition(s, NO_SUN, at(2026, 1, 1, 22, 0)), false)
  assert.equal(M.inTransition(s, NO_SUN, at(2026, 1, 2, 6, 10)), true)
  assert.equal(M.inTransition(fixed({ fadeMinutes: 60, override: { temperature: null, hold: "forever", until: null } }), NO_SUN, at(2026, 1, 1, 20, 30)), false)
})

test("helpers: warmth names, presets, kelvin colors, hyprctl output, locations", () => {
  assert.equal(M.warmthName(6500), "Day")
  assert.equal(M.warmthName(3400), "Night")
  assert.equal(M.warmthName(1900), "Candle")
  assert.equal(M.presetForTemperature(4000), "evening")
  assert.equal(M.presetForTemperature(4100), "")
  const warm = M.kelvinColor(1900)
  assert.equal(warm.r, 1)
  assert.ok(warm.b < 0.3)
  const cool = M.kelvinColor(6500)
  assert.ok(cool.b > 0.9)
  assert.equal(M.temperatureFromOutput("3400\n"), 3400)
  assert.equal(M.temperatureFromOutput("couldn't connect"), null)
  assert.deepEqual(M.parseWeatherLocation('{"name":"Constantina","latitude":-27.7,"longitude":-52.9}'), { name: "Constantina", latitude: -27.7, longitude: -52.9 })
  assert.deepEqual(M.parseWeatherLocation("nope"), { name: "", latitude: null, longitude: null })
  assert.deepEqual(M.parseGeocode('{"results":[{"name":"Lisbon","admin1":"Lisboa","latitude":38.7,"longitude":-9.1}]}'), { latitude: 38.7, longitude: -9.1, name: "Lisbon, Lisboa" })
  assert.equal(M.parseGeocode('{"results":[]}'), null)
})
