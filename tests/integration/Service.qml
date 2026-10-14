import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Plugin

// Drives the real Service.qml against the fake hyprsunset (tests/bin).
// Each step runs once, then the harness polls its `until` check.
ShellRoot {
  id: harness

  readonly property string fake: Quickshell.env("FAKE_HYPRSUNSET")
  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/omarchy/settings/omanight.json"

  function pad(n) { return (n < 10 ? "0" : "") + n }
  function clock(offsetMinutes) {
    var d = new Date(Date.now() + offsetMinutes * 60000)
    return pad(d.getHours()) + ":" + pad(d.getMinutes())
  }

  FileView { id: fakeTemp; path: harness.fake + "/temperature"; blockLoading: true; printErrors: false }
  FileView { id: stateFile; path: harness.statePath; blockLoading: true; printErrors: false }

  function screen() {
    fakeTemp.reload()
    var t = parseInt(String(fakeTemp.text() || "").trim(), 10)
    return isNaN(t) ? null : t
  }
  function saved() {
    stateFile.reload()
    try { return JSON.parse(stateFile.text()) } catch (e) { return null }
  }

  property var service: null
  property int stepIndex: -1
  property int waited: 0
  property bool ran: false

  // Night started an hour ago and ends in ten: the schedule wants 3400K.
  readonly property var steps: [
    { name: "starts hyprsunset and applies the scheduled temperature",
      until: function() { return harness.screen() === 3400 && harness.service.enabled } },
    { name: "adopts the weather widget's coordinates",
      until: function() { return harness.service.prefs.latitude === -27.73472 && harness.service.prefs.locationSource === "weather" } },
    { name: "switching off holds daylight until the next change and persists it",
      run: function() { harness.service.setNightlight(false) },
      until: function() {
        var s = harness.saved()
        return harness.screen() === 6500 && !harness.service.enabled
          && s && s.override && s.override.temperature === null && s.override.hold === "next"
      } },
    { name: "resume returns to the schedule",
      run: function() { harness.service.resume() },
      until: function() { var s = harness.saved(); return harness.screen() === 3400 && s && s.override === null } },
    { name: "a keybinding change followed by refresh becomes an override",
      run: function() {
        writeFake.command = ["sh", "-c", 'echo 4000 >"$1/temperature"', "_", harness.fake]
        writeFake.running = true
        harness.service.refresh()
      },
      until: function() {
        var o = harness.service.prefs.override
        return o && o.temperature === 4000 && harness.screen() === 4000
      } },
    { name: "a silent drift is put back after the grace period",
      run: function() {
        harness.service.resume()
        writeFake.command = ["sh", "-c", 'sleep 1; echo 6500 >"$1/temperature"', "_", harness.fake]
        writeFake.running = true
        driftPoke.start()
      },
      until: function() { return harness.waited > 3500 && harness.screen() === 3400 && harness.service.prefs.override === null } },
    { name: "presets apply with the chosen hold",
      run: function() { harness.service.setHold("1h"); harness.service.applyPreset("candle") },
      until: function() {
        var o = harness.service.prefs.override
        return harness.screen() === 1900 && o && o.hold === "1h" && Math.abs(o.until - Date.now() - 3600000) < 10000
      } },
    { name: "manual mode clears the override and holds the manual temperature",
      run: function() { harness.service.setField("manualTemperature", 2900); harness.service.setMode("manual") },
      until: function() { return harness.screen() === 2900 && harness.service.prefs.override === null } },
    { name: "status payload is JSON with the schedule",
      run: function() { harness.service.setMode("fixed") },
      until: function() {
        var p = JSON.parse(JSON.stringify(harness.service.statusPayload()))
        return p.mode === "fixed" && p.target === 3400 && p.schedule.length === 2 && p.healthy === true
      } }
  ]

  Process { id: writeFake }

  // Simulates the ticks a live shell would deliver while the drift settles.
  Timer {
    id: driftPoke
    interval: 1500; repeat: true
    property int count: 0
    onTriggered: { harness.service.probe(); if (++count >= 4) { stop(); count = 0 } }
  }

  Process {
    id: fixture
    running: true
    command: ["sh", "-c",
      'printf "%s" "$1" >"$3/.local/state/omarchy/settings/weather.json" && printf "%s" "$2" >"$3/.local/state/omarchy/settings/omanight.json"',
      "_",
      JSON.stringify({ name: "Constantina", latitude: -27.73472, longitude: -52.99222 }),
      JSON.stringify({ mode: "fixed", onTime: harness.clock(-60), offTime: harness.clock(600), fadeMinutes: 0, lateAfterMinutes: 0, eveningTemperature: 3400 }),
      harness.home]
    onExited: function(code) {
      if (code !== 0) return harness.finish("could not write fixtures")
      harness.service = serviceComponent.createObject(harness)
      harness.advance()
    }
  }

  Component { id: serviceComponent; Plugin.Service {} }

  function advance() {
    stepIndex++
    waited = 0
    ran = false
    if (stepIndex >= steps.length) return finish("")
    poll.start()
  }

  Timer {
    id: poll
    interval: 100; repeat: true
    onTriggered: {
      var step = harness.steps[harness.stepIndex]
      if (!harness.ran) { harness.ran = true; if (step.run) step.run() }
      harness.waited += interval
      var ok = false
      try { ok = step.until() } catch (e) { console.log("step threw: " + e) }
      if (ok) { stop(); console.log("ok  - " + step.name); harness.advance(); return }
      if (harness.waited > 8000) { stop(); harness.finish("timed out: " + step.name + " (screen " + harness.screen() + ", prefs " + JSON.stringify(harness.service.prefs) + ")") }
    }
  }

  function finish(error) {
    if (error) console.log("NIGHTLIGHT_FAIL " + error)
    else console.log("NIGHTLIGHT_PASS")
    Qt.quit()
  }
}
