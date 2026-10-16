import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup for the night light: what the screen shows now, the switch and a
// kelvin slider. A thin front end to Service.qml, which owns state, runs the
// schedule and talks to hyprsunset; presets, resume, the schedule and the
// rarer knobs are IPC only. A slider change holds until the next scheduled
// change, and a middle click on the moon resumes the schedule.
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
  readonly property int currentTemp: service ? service.displayTemperature : Model.DAY_TEMPERATURE
  readonly property bool overrideActive: service ? service.overrideActive : false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontName: bar ? bar.fontFamily : Style.font.family

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

  onOpenedChanged: if (!opened) cursorActive = false

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

  // ---- Keyboard cursor -------------------------------------------------------

  property bool cursorActive: false
  property string focusSection: "slider"
  property int selectedIndex: 0
  readonly property var sections: ["switch", "slider"]

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
    if (focusSection === "slider" && service) service.setTemperature(currentTemp + dx * 100)
  }
  function activateCursor() {
    if (focusSection === "switch" && service) service.toggle()
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
          title: root.service ? root.service.warmthLabel + " · " + root.currentTemp + "K" : "Night Light"
          meta: root.service ? root.service.statusText : "Service not running"
          foreground: root.fg
          fontFamily: root.fontName
          iconComponent: Component {
            Text {
              text: "󰔎"
              color: root.fg
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
      }
    }
  }
}
