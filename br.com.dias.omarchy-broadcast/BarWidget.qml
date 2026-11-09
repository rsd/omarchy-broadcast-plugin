pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The bar icon and its popup. One of these per monitor; all of them read the
// same Daemon singleton, which owns the only watch process.
//
// Left click turns the camera on or off, but only while the daemon's state is
// known: unavailable, it opens the panel instead, so a persisted `off` the
// user cannot see is never flipped (and `on` never D-Bus-activates a stopped
// daemon). While a command is running or queued it does nothing. Right or
// middle click opens and closes the panel.
BarWidget {
  id: root
  moduleName: "br.com.dias.omarchy-broadcast"

  readonly property var record: Daemon.record
  readonly property var visual: Model.visualFor(Model.visualKey(record))
  readonly property var cliSetting: Model.settingValue(settings, "cliPath")
  readonly property color urgentColor: bar ? bar.urgent : Commons.Color.urgent

  property bool opened: false
  property bool popoutSwitchClosing: false

  // For the test harness: the shared service, the icon and the popup.
  readonly property QtObject service: Daemon
  readonly property Item iconButton: button
  readonly property var popup: panel

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }
  function switchPanel(direction) {
    return bar && typeof bar.switchPanelFrom === "function" ? bar.switchPanelFrom(root, direction) : false
  }

  // "ignore": a command is running or queued, so the result of the last
  // click has not arrived and the target of a toggle is unknown.
  function activate() {
    var action = Model.leftClickAction(root.record, Daemon.commandBusy)
    if (action === "toggle") Daemon.toggleEnabled()
    else if (action === "open-panel") root.open()
  }

  function press(buttonCode) {
    if (buttonCode === Qt.LeftButton) root.activate()
    else root.toggle()
  }

  onCliSettingChanged: Daemon.configure(root, root.cliSetting)

  Component.onCompleted: {
    Daemon.attach(root)
    Daemon.configure(root, root.cliSetting)
  }
  // Hands the registration back, and nothing else: stopping the watch is the
  // singleton's call once no widget is left (a reload destroys every widget).
  Component.onDestruction: Daemon.detach(root)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.visual.glyph
    active: root.visual.colorRole !== "foreground"
    activeColor: root.visual.colorRole === "urgent" ? root.urgentColor : Commons.Color.accent
    dimmed: root.visual.dimmed
    tooltipText: Model.tooltipText(root.record)
    onPressed: function(buttonCode) { root.press(buttonCode) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent ? panel.loadedContent.keyCatcher : null
    contentWidth: panel.fittedContentWidth(Style.space(340))
    // Capped as the shell's own panels are; the content scrolls past it.
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    // Built on first open, not on every monitor at startup.
    content: Component {
      BroadcastPanel {
        bar: root.bar
        opened: root.opened
        onCloseRequested: root.close()
        onSwitchRequested: function(direction) { root.switchPanel(direction) }
      }
    }
  }
}
