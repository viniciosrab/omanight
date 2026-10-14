import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup for the night light: what the screen shows now, quick overrides,
// the schedule editor, and a timeline of tonight. Everything is a thin
// front end to Service.qml, which owns state and talks to hyprsunset.
Panel {
  id: root
  moduleName: "vinicios.nightlight"
  ipcTarget: "vinicios.nightlight"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("vinicios.nightlight") : null
  readonly property var prefs: service ? service.prefs : Model.defaultState()
  readonly property int currentTemp: service ? service.displayTemperature : Model.DAY_TEMPERATURE
  readonly property bool overrideActive: service ? service.overrideActive : false
  readonly property var plan: service ? Model.nightPlan(service.prefs, service.sun) : null
  readonly property var events: service ? service.events : []

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontName: bar ? bar.fontFamily : Style.font.family

  // ---- Lifecycle -------------------------------------------------------------

  function open() {
    root.controller.show()
    if (service) service.tick()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }
  function close() {
    root.controller.hide()
    setCenterHoverRevealSuppressed(false)
  }
  function toggle() { root.opened ? root.close() : root.open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  onOpenedChanged: if (!opened) {
    cursorActive = false
    setCenterHoverRevealSuppressed(false)
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

  readonly property real nowOffset: plan && service ? wrap(Model.minuteOfDay(service.now) - plan.start) : 0
  function wrap(m) { return ((m % 1440) + 1440) % 1440 }
  function eventOffset(e) { return plan ? wrap(e.minute - plan.start) : 0 }
  function activeIndex() {
    if (!plan || events.length === 0) return -1
    if (nowOffset >= plan.length) return events.length - 1
    var active = 0
    for (var i = 0; i < events.length; i++) if (eventOffset(events[i]) <= nowOffset) active = i
    return active
  }
  function fadeProgress(e) {
    if (!plan || overrideActive || e.fadeMinutes <= 0) return -1
    var off = eventOffset(e)
    if (nowOffset < off || nowOffset >= off + e.fadeMinutes) return -1
    return (nowOffset - off) / e.fadeMinutes
  }
  function eventLabel(e) {
    if (e.kind === "evening") return plan && plan.window.source === "sun" ? "Sunset" : "Evening"
    if (e.kind === "late") return "Late"
    return plan && plan.window.source === "sun" ? "Sunrise" : "Day"
  }

  readonly property string sunLine: {
    if (!service) return ""
    var s = service.sun
    var where = prefs.locationName || (service.hasLocation ? prefs.latitude.toFixed(2) + ", " + prefs.longitude.toFixed(2) : "")
    if (!service.hasLocation) return "No location — set one in the Weather widget"
    if (s.polar === "day") return "Polar day at " + where + " — using fixed times"
    if (s.polar === "night") return "Polar night at " + where + " — using fixed times"
    return "Sunset " + Model.formatHHMM(s.sunset) + " · Sunrise " + Model.formatHHMM(s.sunrise) + " · " + where
  }

  // ---- Keyboard cursor -------------------------------------------------------

  property bool cursorActive: false
  property string focusSection: "slider"
  property int selectedIndex: 0
  readonly property var sections: overrideActive
    ? ["switch", "slider", "presets", "hold", "resume", "mode"]
    : ["switch", "slider", "presets", "hold", "mode"]

  function sectionCount(section) {
    if (section === "presets") return Model.PRESETS.length
    if (section === "hold") return Model.HOLDS.length
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
      var next = Math.max(0, Math.min(sections.length - 1, (i < 0 ? 0 : i + dy)))
      focusSection = sections[next]
      selectedIndex = 0
      return
    }
    if (focusSection === "slider") { if (service) service.setTemperature(currentTemp + dx * 100); return }
    var max = sectionCount(focusSection) - 1
    if (max >= 0) selectedIndex = Math.max(0, Math.min(max, selectedIndex + dx))
  }
  function activateCursor() {
    if (!service) return
    if (focusSection === "switch") service.toggle()
    else if (focusSection === "presets") service.applyPreset(Model.PRESETS[selectedIndex].value)
    else if (focusSection === "hold") service.setHold(Model.HOLDS[selectedIndex].value)
    else if (focusSection === "resume") service.resume()
    else if (focusSection === "mode") service.setMode(Model.MODES[selectedIndex])
  }
  function cursorAt(section) { return cursorActive && focusSection === section }

  // ---- Pieces ----------------------------------------------------------------

  // A strip painted in the colours the screen passes through, sampled in
  // mireds like the fades themselves.
  component KelvinBar: Rectangle {
    id: kbar
    property int fromK: 6500
    property int toK: 3400
    property real marker: -1
    height: Style.space(8)
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
    Rectangle {
      visible: kbar.marker >= 0
      width: Style.space(3)
      height: parent.height + Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(kbar.width - width, kbar.width * kbar.marker - width / 2))
      color: root.fg
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
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: onField.activeFocus || offField.activeFocus || eveningField.field.activeFocus
        || lateField.field.activeFocus || lateAfterField.field.activeFocus || fadeField.field.activeFocus
        || manualField.field.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
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
          title: root.service ? root.service.warmthLabel : "Night Light"
          meta: root.service ? root.service.statusText : "Service not running"
          detail: root.currentTemp + "K"
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

        PanelSeparator { foreground: root.fg }

        // ---- Temperature ----
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Style.space(18)
            PanelSectionHeader {
              text: root.overrideActive ? "OVERRIDE" : "TEMPERATURE"
              foreground: root.fg
              fontFamily: root.fontName
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Caption {
              text: root.service && root.service.target.source !== "override"
                ? (root.service.target.source === "manual" ? "manual" : "scheduled") + " " + root.service.targetTemperature + "K"
                : ""
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
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
              fromK: Model.MIN_TEMPERATURE
              toK: Model.MAX_TEMPERATURE
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
        }

        // ---- How long overrides last ----
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "HOLD OVERRIDES UNTIL"; foreground: root.fg; fontFamily: root.fontName }

          ButtonGroup {
            width: parent.width
            options: Model.HOLDS
            value: root.overrideActive && root.prefs.override ? root.prefs.override.hold : root.prefs.defaultHold
            foreground: root.fg
            fontFamily: root.fontName
            focusable: false
            cursorIndex: root.cursorAt("hold") ? root.selectedIndex : -1
            onHovered: function(index, on) { if (on) root.hoverTo("hold", index) }
            onChanged: function(value) { if (root.service) root.service.setHold(value) }
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
        }

        PanelSeparator { foreground: root.fg }

        // ---- Schedule ----
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "SCHEDULE"; foreground: root.fg; fontFamily: root.fontName }

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

          // Fixed times; also the fallback for sun mode without sun times.
          Row {
            width: parent.width
            spacing: Style.space(12)
            visible: root.prefs.mode !== "manual"

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(4)
              Caption { text: root.prefs.mode === "sun" ? "Fallback on" : "Turns on" }
              TextField {
                id: onField
                width: parent.width
                text: root.prefs.onTime
                placeholderText: "20:00"
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
              Caption { text: root.prefs.mode === "sun" ? "Fallback off" : "Turns off" }
              TextField {
                id: offField
                width: parent.width
                text: root.prefs.offTime
                placeholderText: "07:00"
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
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(8)
            visible: root.prefs.mode !== "manual"

            NumberField {
              id: eveningField
              label: "Evening (K)"
              from: Model.MIN_TEMPERATURE; to: Model.MAX_TEMPERATURE; stepSize: 100
              value: root.prefs.eveningTemperature
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("eveningTemperature", v) }
            }
            NumberField {
              id: lateField
              label: "Late (K)"
              from: Model.MIN_TEMPERATURE; to: Model.MAX_TEMPERATURE; stepSize: 100
              value: root.prefs.lateTemperature
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("lateTemperature", v) }
            }
            NumberField {
              id: lateAfterField
              label: "Late after (min, 0 = off)"
              from: 0; to: 720; stepSize: 15
              value: root.prefs.lateAfterMinutes
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("lateAfterMinutes", v) }
            }
            NumberField {
              id: fadeField
              label: "Fade (min, 0 = snap)"
              from: 0; to: Model.MAX_FADE_MINUTES; stepSize: 5
              value: root.prefs.fadeMinutes
              foreground: root.fg; fontFamily: root.fontName
              onModified: function(v) { if (root.service) root.service.setField("fadeMinutes", v) }
            }
          }

          NumberField {
            id: manualField
            visible: root.prefs.mode === "manual"
            label: "Manual temperature (K)"
            from: Model.MIN_TEMPERATURE; to: Model.MAX_TEMPERATURE; stepSize: 100
            value: root.prefs.manualTemperature
            foreground: root.fg; fontFamily: root.fontName
            onModified: function(v) { if (root.service) root.service.setField("manualTemperature", v) }
          }
        }

        // ---- Tonight ----
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.events.length > 0

          PanelSeparator { foreground: root.fg }
          PanelSectionHeader { text: "TONIGHT"; foreground: root.fg; fontFamily: root.fontName }

          Repeater {
            model: root.events

            Column {
              id: eventRow
              required property var modelData
              required property int index
              readonly property bool current: index === root.activeIndex() && !root.overrideActive
              readonly property real progress: root.fadeProgress(modelData)
              width: parent.width
              spacing: Style.space(4)

              Item {
                width: parent.width
                height: Style.space(18)

                Rectangle {
                  id: dot
                  width: Style.space(6); height: width; radius: width / 2
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.fg
                  visible: eventRow.current
                }
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(14)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.formatHHMM(eventRow.modelData.minute) + "   " + root.eventLabel(eventRow.modelData)
                    + (eventRow.modelData.fadeMinutes > 0 ? "  ·  " + eventRow.modelData.fadeMinutes + " min fade" : "")
                  color: eventRow.current ? root.fg : root.dim
                  font.family: root.fontName
                  font.pixelSize: Style.font.body
                  font.bold: eventRow.current
                }
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: eventRow.progress >= 0
                    ? Model.miredMix(eventRow.modelData.fromTemperature, eventRow.modelData.temperature, eventRow.progress) + "K → " + eventRow.modelData.temperature + "K"
                    : (eventRow.modelData.kind === "day" ? "Off" : eventRow.modelData.temperature + "K")
                  color: eventRow.current ? root.fg : root.dim
                  font.family: root.fontName
                  font.pixelSize: Style.font.body
                  font.bold: eventRow.current
                }
              }

              KelvinBar {
                visible: eventRow.modelData.fadeMinutes > 0
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                width: parent.width - Style.space(14)
                fromK: eventRow.modelData.fromTemperature
                toK: eventRow.modelData.temperature
                marker: eventRow.progress
              }
            }
          }
        }
      }
    }
  }
}
