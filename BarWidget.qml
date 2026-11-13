pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The bar icon and its popup. One of these per monitor; all of them read the
// same Daemon singleton, which owns the only watch process, and the same
// Preview singleton, which owns the only preview process: an open panel holds
// the preview (Preview.hold), a closed one releases it.
//
// Left click opens and closes the panel. Middle click turns the camera on or
// off, but only while the daemon's state is known: unavailable, it opens the
// panel instead, so a persisted `off` the user cannot see is never flipped
// (and `on` never D-Bus-activates a stopped daemon). While a command is
// running or queued it does nothing. Right click opens the setup dialog, the
// plugin's overlay, through the shell (openSetup).
//
// While applications record from the Omarchy Broadcast Mic, a microphone
// glyph shows beside the camera's (after it; under it on a vertical bar),
// driven by the watch's `mic` lines: nothing polls. Its left click opens the
// panel and its right click the setup dialog, as the camera icon's; its
// middle click does nothing (the camera's on/off is the camera icon's).
//
// The manifest makes the plugin an overlay as well, so the shell routes the
// plugin's summon and toggle (the panel hotkey) to SetupDialog.qml, which
// forwards them here through the Daemon singleton (Daemon.openPanel, which
// calls open(), and Daemon.closePanels): the hotkey still opens and closes
// this panel.
BarWidget {
  id: root
  moduleName: "br.com.dias.omarchy-broadcast"

  readonly property var record: Daemon.record
  readonly property var visual: Model.visualFor(Model.visualKey(record))
  readonly property var cliSetting: Model.settingValue(settings, "cliPath")
  // The panel tab the settings hold, validated (anything else reads as the
  // default); the panel follows it when it changes.
  readonly property string storedTab: Model.panelTabValue(Model.settingValue(settings, "panelTab"))
  readonly property color urgentColor: bar ? bar.urgent : Commons.Color.urgent
  // The microphone indicator (Model.micIndicator): shown while apps record.
  readonly property var micIndicator: Model.micIndicator(record)

  property bool opened: false
  // The tab a click on the microphone glyph asks for, for this opening only
  // (never written to the layout; the panel shows the stored tab again once
  // it is back to "", which it is at every close).
  property string requestedTab: ""
  property bool popoutSwitchClosing: false
  // For Daemon.panelOwners: this is a bar widget with a panel (the setup
  // dialog attaches to the Daemon too, and is not one).
  readonly property bool panelOwner: true
  // The monitor this copy is drawn on, for the panel the hotkey opens
  // (Daemon.openPanel prefers the focused one).
  readonly property string screenName: root.QsWindow.window && root.QsWindow.window.screen
    ? String(root.QsWindow.window.screen.name || "") : ""

  // For the test harness: the shared services, the icon and the popup.
  readonly property QtObject service: Daemon
  readonly property QtObject previewService: Preview
  readonly property Item iconButton: button
  readonly property Item micButton: micIcon
  readonly property var popup: panel

  implicitWidth: vertical ? button.implicitWidth : button.implicitWidth + (micIcon.visible ? micIcon.implicitWidth : 0)
  implicitHeight: vertical ? button.implicitHeight + (micIcon.visible ? micIcon.implicitHeight : 0) : button.implicitHeight

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

  // The middle click. "ignore": an on/off or other non-control command is
  // running or queued (Daemon.toggleBusy), so the result of the last click
  // has not arrived and the target of a toggle is unknown. Setting writes
  // and the setup dialog's writes do not hold it.
  function toggleCamera() {
    var action = Model.middleClickAction(root.record, Daemon.toggleBusy)
    if (action === "toggle") Daemon.toggleEnabled()
    else if (action === "open-panel") root.open()
  }

  // The right click: the setup dialog, through the shell's toggle of this
  // plugin with the setup payload (the overlay's open() reads it; it names
  // no program to run, only the row to open at). Every open panel closes first:
  // the shell reports the plugin open while one is (SetupDialog.opened), and
  // its toggle would then close instead of open. False, with every panel
  // left as it was, when the shell has no overlay to open (the bar gave no
  // shell, or one without a toggle).
  // `focus`: the key of the config row the dialog opens at (the panel's
  // Away image row), else none.
  function openSetup(focus) {
    var shell = root.bar ? root.bar.shell : null
    if (!shell || typeof shell.toggle !== "function") return false
    Daemon.closePanels()
    return shell.toggle(root.moduleName, Model.setupPayloadJson(focus)) === true
  }

  function press(buttonCode) {
    var action = Model.clickAction(buttonCode === Qt.MiddleButton ? "middle" : (buttonCode === Qt.RightButton ? "right" : "left"),
                                   root.record, Daemon.toggleBusy)
    if (action === "setup") root.openSetup()
    else if (action === "panel") root.toggle()
    else root.toggleCamera()
  }

  // A click on the microphone indicator (Model.micClickAction): left opens
  // the panel on the Mic tab (a transient choice: the stored tab is not
  // written) or closes it when open, right the setup dialog, middle nothing.
  function pressMic(buttonCode) {
    var action = Model.micClickAction(buttonCode === Qt.MiddleButton ? "middle" : (buttonCode === Qt.RightButton ? "right" : "left"),
                                      root.opened)
    if (action === "setup") {
      root.openSetup()
    } else if (action === "open-mic") {
      root.requestedTab = "mic"
      root.open()
    } else if (action === "close") {
      root.close()
    }
  }

  // A user's change in the panel (a preview preference or the tab): in force
  // at once (Preview.choose; the panel holds its own tab), then
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
    if (!root.opened) root.requestedTab = ""
    Daemon.notePanels()
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

  // The camera's icon fills the widget but for the microphone's slot.
  BarIconButton {
    id: button
    x: 0
    y: 0
    width: root.vertical || !micIcon.visible ? root.width : Math.max(0, root.width - micIcon.width)
    height: !root.vertical || !micIcon.visible ? root.height : Math.max(0, root.height - micIcon.height)
    bar: root.bar
    text: root.visual.glyph
    active: root.visual.colorRole !== "foreground"
    activeColor: root.visual.colorRole === "urgent" ? root.urgentColor : Commons.Color.accent
    dimmed: root.visual.dimmed
    tooltipText: Model.tooltipText(root.record)
    onPressed: function(buttonCode) { root.press(buttonCode) }

    // The shell's kit sets no accessible text; the state is the tooltip's,
    // the description says what each click does.
    Accessible.role: Accessible.Button
    Accessible.name: Model.tooltipText(root.record)
    Accessible.description: Model.barClickHelp(root.record)
  }

  BarIconButton {
    id: micIcon
    objectName: "micIndicator"
    visible: root.micIndicator.visible
    x: root.vertical ? 0 : button.width
    y: root.vertical ? button.height : 0
    width: root.vertical ? root.width : implicitWidth
    height: root.vertical ? implicitHeight : root.height
    bar: root.bar
    text: root.micIndicator.glyph
    active: true
    activeColor: root.micIndicator.urgent ? root.urgentColor : Commons.Color.accent
    tooltipText: root.micIndicator.tooltip
    onPressed: function(buttonCode) { root.pressMic(buttonCode) }

    Accessible.role: Accessible.Button
    Accessible.name: root.micIndicator.tooltip
    Accessible.description: "Click: open the panel on the Mic tab, or close it. Right click: open the setup."
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent ? panel.loadedContent.keyCatcher : null
    // 520: wider than the shell's widest panel (weather, 480) because the
    // preview spans the card. With the card's padding (popup-padding 14 a
    // side) and border taken off, the 16:9 frame is about 484x272, so the
    // preview's 480x270 frames show at their own size instead of being scaled
    // down to a blur, and the tab row and the slider rows get room to breathe.
    contentWidth: panel.fittedContentWidth(Style.space(520))
    // Not capped below the screen: the preview, the tab row and the tallest
    // tab fit on a 1080-pixel screen. The card's own limit is the screen's
    // available height (KeyboardPanel.availableCardHeight); only past it does
    // the content scroll.
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    // Built on first open, not on every monitor at startup.
    content: Component {
      BroadcastPanel {
        bar: root.bar
        opened: root.opened
        storedTab: root.storedTab
        requestedTab: root.requestedTab
        // The card's room for the content on this screen: past it the
        // camera settings scroll inside the Camera tab, not the panel.
        contentRoom: panel.availableCardHeight > 0 ? Math.max(0, panel.availableCardHeight - panel.padding * 2) : 0
        onCloseRequested: root.close()
        onSettingsRequested: function(values) { root.persistSettings(values) }
        onSetupRequested: function(focus) { root.openSetup(focus) }
        onSwitchRequested: function(direction) { root.switchPanel(direction) }
      }
    }
  }
}
