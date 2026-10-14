import QtQuick
import qs.Commons
import qs.Ui

// Moon in the bar. Left click opens the panel, right click switches the
// light on or off until the next scheduled change, middle click resumes the
// schedule. With `hideWhenOff` it only shows while the light is on, the
// panel is open, or the bar's center section is hovered.
BarWidget {
  id: root
  moduleName: "vinicios.nightlight"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("vinicios.nightlight") : null
  readonly property bool nightActive: service ? service.enabled : false
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  readonly property bool hideWhenOff: setting("hideWhenOff", false) === true
  readonly property bool revealed: bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true
  readonly property bool shown: !hideWhenOff || nightActive || opened || revealed || button.tooltipHovered

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function handlePress(b) {
    if (!service) { toggle(); return }
    if (b === Qt.RightButton) service.toggle()
    else if (b === Qt.MiddleButton) service.resume()
    else toggle()
  }

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰔎"
    dimmed: !root.nightActive
    tooltipText: root.opened || !root.service ? "" : root.service.displayTemperature + "K · " + root.service.statusText

    onPressed: function(b) { root.handlePress(b) }
  }
}
