import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "host" as Host
import "plugin" as Plugin

// Mounts the bar widget and its panel the way omarchy-shell does (Omarchy's
// own PluginShellApi and PluginBarApi), backed by the real service and the
// fake hyprsunset. Fails on any QML binding or type error in the output.
ShellRoot {
  id: harness

  readonly property string fake: Quickshell.env("FAKE_HYPRSUNSET")
  readonly property string home: Quickshell.env("HOME")

  function pad(n) { return (n < 10 ? "0" : "") + n }
  function clock(offsetMinutes) {
    var d = new Date(Date.now() + offsetMinutes * 60000)
    return pad(d.getHours()) + ":" + pad(d.getMinutes())
  }

  // Read with cat: FileView can miss a same-size rewrite within one second.
  property string fakeTemperature: ""
  Process {
    id: fakeRead
    command: ["cat", harness.fake + "/temperature"]
    stdout: StdioCollector { onStreamFinished: harness.fakeTemperature = text.trim() }
  }
  function screen() {
    var t = parseInt(harness.fakeTemperature, 10)
    return isNaN(t) ? null : t
  }

  property var service: null
  property var widget: null
  readonly property var panel: widget ? widget.children[0].item : null

  Host.PluginShellApi {
    id: hostShell
    pluginId: "vinicios.nightlight"
    _serviceLookup: function(id) { return id === "vinicios.nightlight" ? harness.service : null }
  }

  PluginBarApi {
    id: hostBar
    pluginId: "vinicios.nightlight"
    moduleName: "vinicios.nightlight"
    shell: hostShell
  }

  Component { id: serviceComponent; Plugin.Service {} }
  Component { id: widgetComponent; Plugin.BarWidget { bar: hostBar } }

  readonly property var steps: [
    { name: "widget finds the service and shows the light on",
      until: function() { return harness.widget.service === harness.service && harness.widget.nightActive && harness.screen() === 3400 } },
    { name: "right click switches the light off",
      run: function() { harness.widget.handlePress(Qt.RightButton) },
      until: function() { return !harness.widget.nightActive && harness.screen() === 6500 } },
    { name: "hideWhenOff hides the moon while the light is off",
      run: function() { harness.widget.settings = { hideWhenOff: true } },
      until: function() { return harness.widget.shown === false && harness.widget.implicitWidth === 0 } },
    { name: "middle click resumes the schedule and shows the moon again",
      run: function() { harness.widget.handlePress(Qt.MiddleButton) },
      until: function() { return harness.widget.nightActive && harness.widget.shown && harness.widget.implicitWidth > 0 && harness.screen() === 3400 } },
    { name: "left click opens the panel under the icon with only the switch and the slider",
      run: function() { harness.widget.settings = {}; harness.widget.handlePress(Qt.LeftButton) },
      until: function() {
        var p = harness.panel
        return p && p.opened && p.service === harness.service && p.surface.centerOnBar === false
          && JSON.stringify(p.sections) === JSON.stringify(["switch", "slider"])
      } },
    { name: "panel keyboard: down to the slider, right warms by 100K as an override",
      run: function() {
        var p = harness.panel
        p.cursorActive = true
        p.focusSection = "switch"
        p.moveCursor(0, 1)
        p.moveCursor(1, 0)
      },
      until: function() {
        return harness.screen() === 3500 && harness.panel.overrideActive
          && JSON.stringify(harness.panel.sections) === JSON.stringify(["switch", "slider"])
      } },
    { name: "panel keyboard: the switch turns the light off",
      run: function() {
        var p = harness.panel
        p.moveCursor(0, -1)
        p.activateCursor()
      },
      until: function() { return !harness.service.enabled && harness.screen() === 6500 } },
    { name: "panel closes",
      run: function() { harness.panel.close() },
      until: function() { return !harness.panel.opened } }
  ]

  Process {
    id: fixture
    running: true
    command: ["sh", "-c", 'printf "%s" "$1" >"$2/.local/state/omarchy/settings/omanight.json"', "_",
      JSON.stringify({ mode: "fixed", onTime: harness.clock(-60), offTime: harness.clock(600), fadeMinutes: 30, lateAfterMinutes: 180 }),
      harness.home]
    onExited: function(code) {
      if (code !== 0) return harness.finish("could not write fixtures")
      harness.service = serviceComponent.createObject(harness)
      harness.widget = widgetComponent.createObject(harness)
      harness.advance()
    }
  }

  property int stepIndex: -1
  property int waited: 0
  property bool ran: false

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
      if (!fakeRead.running) fakeRead.running = true
      var step = harness.steps[harness.stepIndex]
      if (!harness.ran) { harness.ran = true; if (step.run) step.run() }
      harness.waited += interval
      var ok = false
      try { ok = step.until() } catch (e) { console.log("step threw: " + e) }
      if (ok) { stop(); console.log("ok  - " + step.name); harness.advance(); return }
      if (harness.waited > 8000) { stop(); harness.finish("timed out: " + step.name + " (screen " + harness.screen() + ", override " + JSON.stringify(harness.service.prefs.override) + ", target " + harness.service.targetTemperature + ", enabled " + harness.service.enabled + ")") }
    }
  }

  function finish(error) {
    console.log(error ? "NIGHTLIGHT_FAIL " + error : "NIGHTLIGHT_PASS")
    Qt.quit()
  }
}
