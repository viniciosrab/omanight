import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns the night light. The schedule lives here, not in hyprsunset.conf:
// every tick works out the temperature the screen should show and hands it
// to hyprsunset over IPC. That keeps overrides from being undone by a
// hyprsunset profile switch, makes fades smooth, and leaves the user's
// hyprsunset.conf untouched.
//
// Replaces the stock omarchy.nightlight service (manifest clonedFrom), so it
// keeps that service's surface: `enabled`, `setNightlight()`, and the
// `nightlight` IPC target with status/refresh/enable/disable/toggle.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string settingsDir: Quickshell.env("HOME") + "/.local/state/omarchy/settings"
  readonly property string statePath: settingsDir + "/omanight.json"
  readonly property string weatherPath: settingsDir + "/weather.json"

  // ---- State ---------------------------------------------------------------

  // Named prefs because Item already has a `state` property.
  property var prefs: Model.defaultState()
  property bool stateLoaded: false
  property date now: new Date()
  property var sun: ({ sunrise: null, sunset: null, polar: null })
  property string sunDay: ""

  // What hyprsunset is showing, as last applied or read back.
  property var temperature: null
  property bool healthy: true
  property bool probed: false

  readonly property bool enabled: Model.isNight(temperature)
  readonly property bool hasLocation: Model.hasCoordinates(prefs.latitude, prefs.longitude)
  readonly property var target: Model.targetTemperature(prefs, sun, now)
  readonly property int targetTemperature: target.temperature
  readonly property bool overrideActive: Model.overrideActive(prefs, now)
  readonly property bool transitioning: Model.inTransition(prefs, sun, now)
  readonly property string statusText: Model.statusText(prefs, sun, now, hasLocation)
  readonly property var events: Model.scheduleEvents(prefs, sun)
  readonly property int displayTemperature: temperature !== null && temperature !== undefined ? temperature : targetTemperature
  readonly property string warmthLabel: Model.warmthName(displayTemperature)

  // ---- Persistence ----------------------------------------------------------

  function update(patch) {
    var next = JSON.parse(JSON.stringify(prefs))
    for (var key in patch) next[key] = patch[key]
    prefs = Model.parseState(JSON.stringify(next))
    recomputeSun()
    if (stateLoaded) saveTimer.restart()
    tick()
  }

  property string lastWritten: ""

  function save() {
    lastWritten = Model.serializeState(prefs)
    stateFile.setText(lastWritten)
  }

  function loadState(raw) {
    prefs = Model.parseState(raw)
    stateLoaded = true
    recomputeSun()
    // weather.json usually loads first, while there is no state to apply it to.
    adoptWeatherLocation(weatherRaw)
    tick()
  }

  property string weatherRaw: ""

  // ---- Sun and location ------------------------------------------------------

  function dayKey(date) {
    return date.getFullYear() + "-" + date.getMonth() + "-" + date.getDate()
  }

  function recomputeSun() {
    sunDay = dayKey(now)
    sun = Model.sunTimes(prefs.latitude, prefs.longitude, now)
  }

  function setLocation(lat, lon, name, source) {
    if (!Model.hasCoordinates(lat, lon)) return false
    update({ latitude: Number(lat), longitude: Number(lon), locationName: String(name || ""), locationSource: source })
    return true
  }

  function adoptWeatherLocation(raw) {
    if (!stateLoaded || prefs.locationSource === "manual") return
    var loc = Model.parseWeatherLocation(raw)
    if (Model.hasCoordinates(loc.latitude, loc.longitude)) {
      if (loc.latitude !== prefs.latitude || loc.longitude !== prefs.longitude || loc.name !== prefs.locationName)
        setLocation(loc.latitude, loc.longitude, loc.name, "weather")
      return
    }
    // A named place without coordinates: look it up once.
    if (loc.name && (!hasLocation || loc.name !== prefs.locationName)) geocode(loc.name)
  }

  function geocode(name) {
    if (geocodeProc.running || !name) return
    geocodeProc.command = ["curl", "-fsS", "--max-time", "8",
      "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=" + encodeURIComponent(name)]
    geocodeProc.running = true
  }

  // ---- Driving hyprsunset ------------------------------------------------------

  property int lastApplied: -1
  property int pendingApply: -1
  property bool adoptOnProbe: false
  property real driftSince: 0

  function tick() {
    now = new Date()
    if (dayKey(now) !== sunDay) recomputeSun()
    if (prefs.override && !Model.overrideActive(prefs, now)) {
      update({ override: null })
      return
    }
    armOverrideTimer()
    if (!stateLoaded) return
    if (targetTemperature !== lastApplied) apply(targetTemperature)
    else probe()
  }

  function apply(temp) {
    lastApplied = temp
    temperature = temp
    driftSince = 0
    if (applyProc.running) { pendingApply = temp; return }
    applyProc.command = ["bash", "-c",
      'if ! pgrep -x hyprsunset >/dev/null; then ' +
      '  if command -v uwsm-app >/dev/null; then setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & ' +
      '  else setsid hyprsunset >/dev/null 2>&1 & fi; fi; ' +
      // A freshly started hyprsunset applies its own temperature at the end
      // of its boot, overriding anything sent earlier, so resend until it sticks.
      'for i in $(seq 1 15); do hyprctl hyprsunset temperature "$1" >/dev/null 2>&1; ' +
      '[ "$(hyprctl hyprsunset temperature 2>/dev/null | head -n1 | tr -d "[:space:]")" = "$1" ] && exit 0; ' +
      'sleep 0.2; done; exit 1',
      "_", String(temp)]
    applyProc.running = true
  }

  function probe() {
    if (applyProc.running || probeProc.running) return
    probeProc.running = true
  }

  function onProbed(value) {
    probed = true
    healthy = value !== null
    if (applyProc.running) return
    if (adoptOnProbe) {
      adoptOnProbe = false
      var adopted = Model.adoptExternal(prefs, sun, now, value)
      if (adopted !== undefined) {
        // Already on screen; record it rather than re-sending it.
        lastApplied = adopted.temperature === null ? Model.DAY_TEMPERATURE : adopted.temperature
        temperature = value
        update({ override: adopted })
        return
      }
    }
    temperature = value
    if (value === targetTemperature) { driftSince = 0; return }
    // hyprsunset changed without us: its own profile switch, a restart, or a
    // keybinding that is about to call `nightlight refresh`. Give the last a
    // moment to arrive, then put the schedule back.
    if (value !== null) {
      if (driftSince === 0) {
        driftSince = Date.now()
        driftTimer.restart()
        return
      }
      if (Date.now() - driftSince < 2500) return
    }
    apply(targetTemperature)
  }

  function armOverrideTimer() {
    var o = prefs.override
    if (!o || o.until === null || o.until === undefined) { overrideTimer.stop(); return }
    var ms = o.until - Date.now()
    if (ms <= 0) { overrideTimer.stop(); return }
    overrideTimer.interval = Math.min(ms + 50, 3600000)
    overrideTimer.restart()
  }

  // ---- Actions (panel, bar, IPC) -------------------------------------------------

  function setNightlight(value) {
    update({ override: Model.toggleOverride(prefs, sun, new Date(), !!value) })
  }

  function toggle() {
    setNightlight(!enabled)
  }

  // `temp` null means off. `hold` defaults to the panel's chosen hold.
  function setOverride(temp, hold) {
    var h = hold || prefs.defaultHold
    try {
      update({ override: Model.makeOverride(temp, h, prefs, sun, new Date()) })
      return true
    } catch (error) {
      return false
    }
  }

  function setTemperature(temp) {
    return setOverride(Model.clampTemperature(temp, targetTemperature), "")
  }

  function applyPreset(name) {
    var t = Model.presetTemperature(name)
    if (t === null) return false
    return setOverride(t >= Model.IDENTITY_TEMPERATURE ? null : t, "")
  }

  // Choose how long overrides last; re-times the active one too.
  function setHold(hold) {
    var patch = {}
    var known = Model.HOLDS.some(function(h) { return h.value === hold })
    if (known) patch.defaultHold = hold
    if (overrideActive) {
      try {
        patch.override = Model.makeOverride(prefs.override.temperature, hold, prefs, sun, new Date())
      } catch (error) {
        return false
      }
    } else if (!known) {
      return false
    }
    update(patch)
    return true
  }

  function resume() {
    update({ override: null })
  }

  function setMode(mode) {
    if (Model.MODES.indexOf(mode) === -1) return false
    update({ mode: mode, override: null })
    return true
  }

  function setSchedule(onTime, offTime) {
    if (Model.parseHHMM(onTime) === null || Model.parseHHMM(offTime) === null) return false
    update({ onTime: onTime, offTime: offTime })
    return true
  }

  function setField(key, value) {
    var patch = {}
    patch[key] = value
    update(patch)
  }

  function refresh() {
    adoptOnProbe = true
    probe()
  }

  function statusPayload() {
    return {
      enabled: enabled,
      temperature: temperature,
      target: targetTemperature,
      source: target.source,
      status: statusText,
      healthy: healthy,
      mode: prefs.mode,
      override: overrideActive ? prefs.override : null,
      sunrise: sun.sunrise === null ? null : Model.formatHHMM(sun.sunrise),
      sunset: sun.sunset === null ? null : Model.formatHHMM(sun.sunset),
      polar: sun.polar,
      location: hasLocation ? { name: prefs.locationName, latitude: prefs.latitude, longitude: prefs.longitude, source: prefs.locationSource } : null,
      schedule: events.map(function(e) {
        return { at: Model.formatHHMM(e.minute), kind: e.kind, temperature: e.temperature, fadeMinutes: e.fadeMinutes }
      })
    }
  }

  // ---- Timers and processes ---------------------------------------------------

  Timer {
    id: saveTimer
    interval: 300
    onTriggered: root.save()
  }

  Timer {
    id: ticker
    interval: root.transitioning ? 2000 : 30000
    running: root.stateLoaded
    repeat: true
    onTriggered: root.tick()
  }

  Timer {
    id: overrideTimer
    repeat: false
    onTriggered: root.tick()
  }

  Timer {
    id: driftTimer
    interval: 3000
    onTriggered: root.probe()
  }

  // Wakes the schedule on whole minutes (and after suspend).
  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: root.tick()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (!root.stateLoaded) { root.loadState(text()); return }
      // An edit made by hand; ours round-trip to the same prefs.
      var parsed = Model.parseState(text())
      if (JSON.stringify(parsed) !== JSON.stringify(root.prefs)) {
        root.prefs = parsed
        root.recomputeSun()
        root.tick()
      }
    }
    onLoadFailed: if (!root.stateLoaded) root.loadState("")
  }

  FileView {
    id: weatherFile
    path: root.weatherPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.weatherRaw = text()
      root.adoptWeatherLocation(root.weatherRaw)
    }
  }

  Process {
    id: ensureDir
    command: ["mkdir", "-p", root.settingsDir]
    onExited: if (!root.stateLoaded) stateFile.reload()
  }

  Process {
    id: applyProc
    onExited: function(exitCode) {
      root.healthy = exitCode === 0
      if (root.pendingApply !== -1) {
        var t = root.pendingApply
        root.pendingApply = -1
        root.apply(t)
      }
    }
  }

  Process {
    id: probeProc
    command: ["hyprctl", "hyprsunset", "temperature"]
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: probeProc.output = text
    }
    onExited: function(exitCode) {
      root.onProbed(exitCode === 0 ? Model.temperatureFromOutput(output) : null)
      output = ""
    }
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var loc = Model.parseGeocode(text)
        if (loc) root.setLocation(loc.latitude, loc.longitude, loc.name, "geocode")
      }
    }
  }

  Component.onCompleted: ensureDir.running = true

  IpcHandler {
    target: "nightlight"

    function status(): string { return JSON.stringify(root.statusPayload()) }
    function refresh(): void { root.refresh() }
    function enable(): string { root.setNightlight(true); return "enabled" }
    function disable(): string { root.setNightlight(false); return "disabled" }
    function toggle(): string {
      var enabling = !root.enabled
      root.setNightlight(enabling)
      return enabling ? "enabled" : "disabled"
    }
    function setTemperature(kelvin: string): string {
      return root.setTemperature(Number(kelvin)) ? "ok" : "error: bad temperature"
    }
    function preset(name: string): string {
      return root.applyPreset(name) ? "ok" : "error: presets are day, evening, night, candle"
    }
    function off(hold: string): string {
      return root.setOverride(null, hold) ? "ok" : "error: holds are next, morning, 1h, 30m, HH:MM, forever"
    }
    function hold(hold: string): string {
      return root.setHold(hold) ? "ok" : "error: holds are next, morning, 1h, 30m, HH:MM, forever"
    }
    function resume(): string { root.resume(); return "ok" }
    function setMode(mode: string): string {
      return root.setMode(mode) ? mode : "error: modes are sun, fixed, manual"
    }
    function setSchedule(onTime: string, offTime: string): string {
      return root.setSchedule(onTime, offTime) ? "ok" : "error: times are HH:MM"
    }
    function setEvening(kelvin: string): string { root.setField("eveningTemperature", Number(kelvin)); return String(root.prefs.eveningTemperature) }
    function setLate(kelvin: string): string { root.setField("lateTemperature", Number(kelvin)); return String(root.prefs.lateTemperature) }
    function setLateAfter(minutes: string): string { root.setField("lateAfterMinutes", Number(minutes)); return String(root.prefs.lateAfterMinutes) }
    function setFade(minutes: string): string { root.setField("fadeMinutes", Number(minutes)); return String(root.prefs.fadeMinutes) }
    function setManual(kelvin: string): string { root.setField("manualTemperature", Number(kelvin)); return String(root.prefs.manualTemperature) }
    function setLocation(latitude: string, longitude: string): string {
      return root.setLocation(Number(latitude), Number(longitude), "", "manual") ? "ok" : "error: bad coordinates"
    }
    function useWeatherLocation(): string {
      root.update({ locationSource: "" })
      root.adoptWeatherLocation(root.weatherRaw)
      return "ok"
    }
  }
}
