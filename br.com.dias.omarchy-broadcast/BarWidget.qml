pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The bar icon and its popup. One of these per monitor; all of them read the
// same Daemon singleton, which owns the only watch process, and the same
// Preview singleton, which owns the only preview process: an open panel holds
// the preview (Preview.hold), a closed one releases it.
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

  // For the test harness: the shared services, the icon and the popup.
  readonly property QtObject service: Daemon
  readonly property QtObject previewService: Preview
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

  // A user's change in the panel: in force at once (Preview.choose), then
  // written to this widget's layout entry, merged over the settings the bar
  // gave it (a write replaces the entry), as the shell's own panels do. Once
  // stored, this widget takes the entry at once (the shell's write comes back
  // through the bar as the same value). When the shell stores nothing (no
  // layout entry to write, or an entry over Model.SETTINGS_KEY_CAP), the
  // choice holds for this session and the panel says it was not saved
  // (Preview.unsaved); the settings stay as the bar gave them, so another
  // widget re-injected with the same entry cannot undo it. Returns whether
  // the shell stored it. Never called on a read: defaults are not written back.
  function persistSettings(values) {
    Preview.choose(values)
    var entry = Model.settingsEntry(root.moduleName, root.settings, values)
    if (!entry) return false
    var stored = false
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      stored = root.bar.shell.updateEntryInline(root.moduleName, entry) === true
    // false is also the shell's answer for an entry that already held this.
    if (!stored && !Model.settingsHold(root.settings, values)) return false
    root.settings = Model.settingsFromEntry(entry)
    return true
  }

  onCliSettingChanged: Daemon.configure(root, root.cliSetting)
  // Every hand-over of the bar, including the first (there is no earlier
  // call: before it, `settings` is the base's empty default).
  onSettingsChanged: Preview.configure(root, root.settings)
  onOpenedChanged: {
    if (root.opened) Preview.hold(root)
    else Preview.release(root)
  }

  Component.onCompleted: {
    Daemon.attach(root)
    Daemon.configure(root, root.cliSetting)
  }
  // Hands the registrations back, and nothing else: stopping the watch or the
  // preview is the singletons' call once nobody holds them (a reload destroys
  // every widget, and a panel open at that moment gets no close event).
  Component.onDestruction: {
    Daemon.detach(root)
    Preview.release(root)
  }

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
        onSettingsRequested: function(values) { root.persistSettings(values) }
        onSwitchRequested: function(direction) { root.switchPanel(direction) }
      }
    }
  }
}
