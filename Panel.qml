import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup for the night light. Kept to what gets used day to day: what the
// screen shows now, the switch, a slider, presets, and a way back to the
// schedule. The schedule editor stays collapsed until asked for. Everything
// is a thin front end to Service.qml, which owns state and talks to
// hyprsunset; the rarer knobs (hold length, late-stage delay) are IPC only.
Panel {
  id: root
  moduleName: "vinicios.nightlight"
  ipcTarget: "vinicios.nightlight"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property alias surface: panel

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("vinicios.nightlight") : null
  readonly property var prefs: service ? service.prefs : Model.defaultState()
  readonly property int currentTemp: service ? service.displayTemperature : Model.DAY_TEMPERATURE
  readonly property bool overrideActive: service ? service.overrideActive : false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontName: bar ? bar.fontFamily : Style.font.family

  property bool scheduleExpanded: false

  // ---- Lifecycle -------------------------------------------------------------

  function open() {
    root.controller.show()
    if (service) service.tick()
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: if (!opened) {
    cursorActive = false
    scheduleExpanded = false
  }

  IpcHandler {
    target: "vinicios.nightlight"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ---- Helpers ---------------------------------------------------------------

  function kelvinQt(k) {
    var c = Model.kelvinColor(k)
    return Qt.rgba(c.r, c.g, c.b, 1)
  }
  function miredColor(fromK, toK, t) { return kelvinQt(Model.miredMix(fromK, toK, t)) }

  readonly property string scheduleSummary: {
    if (!service) return ""
    var p = prefs
    if (p.mode === "manual") return "Manual · " + p.manualTemperature + "K"
    var w = Model.nightWindow(p, service.sun)
    var times = w ? Model.formatHHMM(w.start) + " → " + Model.formatHHMM(w.end) : ""
    var temps = p.lateAfterMinutes > 0 ? p.eveningTemperature + " / " + p.lateTemperature + "K" : p.eveningTemperature + "K"
    return (p.mode === "sun" && w && w.source === "sun" ? "Sun" : "Fixed") + " · " + times + " · " + temps
  }

  readonly property string sunLine: {
    if (!service) return ""
    if (!service.hasLocation) return "No location — set one in the Weather widget. Using the times below."
    var where = prefs.locationName || prefs.latitude.toFixed(2) + ", " + prefs.longitude.toFixed(2)
    if (service.sun.polar) return "No sunset at " + where + " today. Using the times below."
    return "Following sunset and sunrise at " + where + "."
  }

  // ---- Keyboard cursor -------------------------------------------------------

  property bool cursorActive: false
  property string focusSection: "slider"
  property int selectedIndex: 0
  readonly property var sections: {
    var out = ["switch", "slider", "presets"]
    if (overrideActive) out.push("resume")
    out.push("schedule")
    if (scheduleExpanded) out.push("mode")
    return out
  }

  function sectionCount(section) {
    if (section === "presets") return Model.PRESETS.length
    if (section === "mode") return Model.MODES.length
    return 0
  }
  function hoverTo(section, index) {
    cursorActive = true
    focusSection = section
    selectedIndex = index
  }
  function moveCursor(dx, dy) {
    if (dy !== 0) {
      var i = sections.indexOf(focusSection)
      focusSection = sections[Math.max(0, Math.min(sections.length - 1, (i < 0 ? 0 : i + dy)))]
      selectedIndex = 0
      return
    }
    if (focusSection === "slider") { if (service) service.setTemperature(currentTemp + dx * 100); return }
    var max = sectionCount(focusSection) - 1
    if (max >= 0) selectedIndex = Math.max(0, Math.min(max, selectedIndex + dx))
  }
  function activateCursor() {
    if (focusSection === "schedule") { scheduleExpanded = !scheduleExpanded; return }
    if (!service) return
    if (focusSection === "switch") service.toggle()
    else if (focusSection === "presets") service.applyPreset(Model.PRESETS[selectedIndex].value)
    else if (focusSection === "resume") service.resume()
    else if (focusSection === "mode") service.setMode(Model.MODES[selectedIndex])
  }
  function cursorAt(section) { return cursorActive && focusSection === section }

  // ---- Pieces ----------------------------------------------------------------

  // The slider track, painted in the colours each temperature gives the
  // screen, sampled in mireds so the middle of the bar looks like the middle.
  component KelvinBar: Rectangle {
    id: kbar
    property int fromK: 1000
    property int toK: 6500
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    border.width: 1
    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: root.miredColor(kbar.fromK, kbar.toK, 0) }
      GradientStop { position: 0.25; color: root.miredColor(kbar.fromK, kbar.toK, 0.25) }
      GradientStop { position: 0.5; color: root.miredColor(kbar.fromK, kbar.toK, 0.5) }
      GradientStop { position: 0.75; color: root.miredColor(kbar.fromK, kbar.toK, 0.75) }
      GradientStop { position: 1.0; color: root.miredColor(kbar.fromK, kbar.toK, 1) }
    }
  }

  component Caption: Text {
    color: root.dim
    font.family: root.fontName
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }

  // ---- Surface ---------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: onField.activeFocus || offField.activeFocus || eveningField.field.activeFocus
        || lateField.field.activeFocus || fadeField.field.activeFocus || manualField.field.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") { root.scheduleExpanded = !root.scheduleExpanded; return }
        if (!root.service) return
        if (t === "t" || t === "T") root.service.toggle()
        else if (t === "r" || t === "R") root.service.resume()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: root.service ? root.service.warmthLabel + " · " + root.currentTemp + "K" : "Night Light"
          meta: root.service ? root.service.statusText : "Service not running"
          foreground: root.fg
          fontFamily: root.fontName
          iconComponent: Component {
            Text {
              text: "󰔎"
              color: root.kelvinQt(root.currentTemp)
              font.family: root.fontName
              font.pixelSize: Style.font.display
              opacity: root.service && root.service.enabled ? 1.0 : 0.55
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              checked: root.service ? root.service.enabled : false
              foreground: root.fg
              hasCursor: root.cursorAt("switch")
              onHovered: function(on) { if (on) root.hoverTo("switch", 0) }
              onToggled: if (root.service) root.service.toggle()
            }
          }
        }

        // hyprsunset stopped answering: say so instead of showing stale numbers.
        Row {
          width: parent.width
          spacing: Style.space(10)
          visible: root.service !== null && root.service.probed && !root.service.healthy
          Text {
            width: parent.width - retryButton.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: "hyprsunset is not responding"
            color: Color.urgent
            font.family: root.fontName
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          Button {
            id: retryButton
            text: "Retry"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontName
            onClicked: if (root.service) root.service.apply(root.service.targetTemperature)
          }
        }

        CursorSurface {
          width: parent.width
          height: slider.implicitHeight + Style.spacing.controlGap
          hasCursor: root.cursorAt("slider")
          foreground: root.fg
          outline: true

          KelvinBar {
            anchors.left: slider.left
            anchors.right: slider.right
            anchors.verticalCenter: slider.verticalCenter
            height: slider.trackHeight
          }

          PanelSlider {
            id: slider
            bar: root.bar
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            minimum: Model.MIN_TEMPERATURE
            maximum: Model.MAX_TEMPERATURE
            step: 50
            integer: true
            value: root.currentTemp
            trackColor: "transparent"
            fillColor: "transparent"
            onMoved: function(v) { if (root.service) root.service.setTemperature(v) }
            onReleased: function(v) { if (root.service) root.service.setTemperature(v) }
          }

          HoverHandler { onHoveredChanged: if (hovered) root.hoverTo("slider", 0) }
        }

        ButtonGroup {
          width: parent.width
          options: Model.PRESETS
          value: Model.presetForTemperature(root.currentTemp)
          foreground: root.fg
          fontFamily: root.fontName
          focusable: false
          cursorIndex: root.cursorAt("presets") ? root.selectedIndex : -1
          onHovered: function(index, on) { if (on) root.hoverTo("presets", index) }
          onChanged: function(value) { if (root.service) root.service.applyPreset(value) }
        }

        Button {
          width: parent.width
          visible: root.overrideActive
          text: "Resume schedule"
          bordered: true
          foreground: root.fg
          fontFamily: root.fontName
          hasCursor: root.cursorAt("resume")
          onHovered: function(on) { if (on) root.hoverTo("resume", 0) }
          onClicked: if (root.service) root.service.resume()
        }

        PanelSeparator { foreground: root.fg }

        // ---- Schedule: one summary line until expanded ----
        CursorSurface {
          width: parent.width
          height: Style.space(28)
          hasCursor: root.cursorAt("schedule")
          foreground: root.fg

          PanelSectionHeader {
            text: "SCHEDULE"
            foreground: root.fg
            fontFamily: root.fontName
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
          }
          Caption {
            text: root.scheduleSummary + "  " + (root.scheduleExpanded ? "▾" : "▸")
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hoverTo("schedule", 0)
            onClicked: root.scheduleExpanded = !root.scheduleExpanded
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.scheduleExpanded

          ButtonGroup {
            width: parent.width
            options: [
              { value: "sun", label: "Sun" },
              { value: "fixed", label: "Fixed times" },
              { value: "manual", label: "Manual" }
            ]
            value: root.prefs.mode
            foreground: root.fg
            fontFamily: root.fontName
            focusable: false
            cursorIndex: root.cursorAt("mode") ? root.selectedIndex : -1
            onHovered: function(index, on) { if (on) root.hoverTo("mode", index) }
            onChanged: function(value) { if (root.service) root.service.setMode(value) }
          }

          Caption {
            width: parent.width
            visible: root.prefs.mode === "sun"
            text: root.sunLine
            wrapMode: Text.Wrap
          }

          // Fixed times; in sun mode they only apply without a sunset.
          Row {
            width: parent.width
            spacing: Style.space(12)
            visible: root.prefs.mode === "fixed" || (root.prefs.mode === "sun" && root.service !== null
              && (!root.service.hasLocation || !!root.service.sun.polar))

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(4)
              Caption { text: "Turns on" }
              TextField {
                id: onField
                width: parent.width
                text: root.prefs.onTime
                inputMask: "99:99"
                foreground: root.fg
                font.family: root.fontName
                onEditingFinished: {
                  if (root.service) root.service.setSchedule(text, root.prefs.offTime)
                  text = Qt.binding(function() { return root.prefs.onTime })
                }
              }
            }
            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(4)
              Caption { text: "Turns off" }
              TextField {
                id: offField
                width: parent.width
                text: root.prefs.offTime
                inputMask: "99:99"
                foreground: root.fg
                font.family: root.fontName
                onEditingFinished: {
                  if (root.service) root.service.setSchedule(root.prefs.onTime, text)
                  text = Qt.binding(function() { return root.prefs.offTime })
                }
              }
            }
          }

          Grid {
            width: parent.width
            columns: 3
            columnSpacing: Style.space(10)
            visible: root.prefs.mode !== "manual"

            NumberField {
              id: eveningField
              label: "Night (K)"
              fieldWidth: (parent.width - 2 * parent.columnSpacing) / 3
              from: Model.MIN_TEMPERATURE; to: Model.MAX_TEMPERATURE; stepSize: 100
              value: root.prefs.eveningTemperature
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("eveningTemperature", v) }
            }
            NumberField {
              id: lateField
              label: "Late (K)"
              fieldWidth: (parent.width - 2 * parent.columnSpacing) / 3
              from: Model.MIN_TEMPERATURE; to: Model.MAX_TEMPERATURE; stepSize: 100
              value: root.prefs.lateTemperature
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("lateTemperature", v) }
            }
            NumberField {
              id: fadeField
              label: "Fade (min)"
              fieldWidth: (parent.width - 2 * parent.columnSpacing) / 3
              from: 0; to: Model.MAX_FADE_MINUTES; stepSize: 5
              value: root.prefs.fadeMinutes
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("fadeMinutes", v) }
            }
          }

          NumberField {
            id: manualField
            visible: root.prefs.mode === "manual"
            label: "Temperature (K)"
            from: Model.MIN_TEMPERATURE; to: Model.MAX_TEMPERATURE; stepSize: 100
            value: root.prefs.manualTemperature
            foreground: root.fg; fontFamily: root.fontName
            onModified: function(v) { if (root.service) root.service.setField("manualTemperature", v) }
          }
        }
      }
    }
  }
}
