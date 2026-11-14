pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The popup's content, top to bottom: the header (state and switch), the
// daemon's error or the last command's failure, the live preview in a fixed
// 16:9 area with its switch and rate on one row under it, then four tabs:
//   Effect  the background effect's choices as the daemon's settings schema
//           offers them (the options of its mode setting; none named here),
//           the background image it holds (from interface revision 15 the
//           Background row: a thumbnail, the image's name, Gallery... and
//           Add...; before it a read-only row), from revision 17 an Away
//           image... button that opens the setup dialog at the away image's
//           row, from revision 22 the Battery saver switch and under it
//           its Mode dropdown (the mode the switch turns on), then the
//           daemon's other global
//           settings (strength, noise removal, ...) drawn generically, or
//           the hint that replaces them (a daemon below revision 9);
//   Camera  the camera list and Next camera, then from interface revision
//           20 the active camera's health (the rate it really delivers when
//           short of its mode's, the daemon's warnings about it, and effect
//           suggestions, each with its button, the first shown and the
//           rest behind a line that opens them), then the camera's settings
//           as the daemon publishes them: Use recommended settings on its
//           title's line and the changes it would make folded to one line
//           that opens their list, when there are any, then SettingsView
//           (groups that open and close, a widget per type, Reset to
//           defaults), or the hint that replaces them;
//   Mic     the Omarchy Broadcast Mic: its own switch (`mic on|off`), its
//           state, the apps recording from it, the delay its processing
//           adds, the modules it runs on and its error, then its settings
//           as the daemon publishes them (the groups of surface "mic":
//           processing, input device, the default-microphone actions, the
//           audio modules' effects), drawn by the same renderer, or the
//           hint that replaces it all (a daemon below revision 13);
//   Status  state, camera, consumers (by kind where the daemon splits them),
//           output mode, PipeWire output, the daemon's interface revision,
//           and the live figures while active.
// Only the chosen tab is drawn. Everything shown comes out of Model.js
// already sanitised, and every Text here is PlainText as well
// (tests/check-source.py counts them).
//
// Nothing here changes state directly: a control runs a CLI command through
// the Daemon singleton, and the result arrives on the watch stream. The
// preview's two controls and the tab are preferences: they ask the widget to
// write its layout entry (settingsRequested); the Preview singleton follows
// the preview ones, and this panel holds its own tab. The preview shows what
// apps receive: black while the camera is idle or an effect loads. Opening the
// panel never starts the camera.
//
// The card is sized to its content (see BarWidget.qml); the panel's
// Flickable only scrolls when the screen is too short for the part above the
// camera settings. One settings group is open at a time, so the tab is never
// taller than its tallest group; past the screen's room (`contentRoom`) the
// groups scroll on their own, inside the Camera tab, under the settings'
// title line that holds Reset to defaults (never scrolled away), so opening
// a group never scrolls the whole panel.
//
// Keyboard, as in the shell's own panels (PanelKeyCatcher, CursorSurface):
// the first arrow key shows the cursor on the on/off switch; Up/Down (or k/j)
// then walk the switch, the Preview switch, the preview-rate row, the tab row
// and the stops of the tab shown (Model.cursorStops); Left/Right (or h/l)
// change the tab on the tab row, walk the preview-rate, effect and a
// setting's choices and the Background row's two buttons (nothing is
// written or run until Enter or Space), move a
// slider, and open (Right) or close (Left) a settings group; 1 to 4 show
// the Effect, Camera, Mic and Status tab from anywhere; Enter or Space activates
// (a group header opens or closes, a choice is made, a dropdown opens its
// list, a switch flips, an action runs); Escape closes; Tab moves to the
// neighbouring panel. The mouse moves the same cursor, so only one highlight
// is ever drawn.
Item {
  id: root

  property QtObject bar: null
  // The popup's open state, from the widget: reopening resets the cursor.
  property bool opened: false
  // The tab the widget's settings hold (Model.panelTabValue, so always a word
  // of Model.PANEL_TABS). The tab in force follows it only when it changes,
  // so a widget re-injected with the same entry never undoes a choice the
  // shell could not store.
  property string storedTab: Model.PANEL_TAB_DEFAULT
  // The Battery saver mode the settings hold (Model.batterySaverModeValue):
  // what the switch turns on, the last mode that was not `off` or the last
  // one chosen in the Mode dropdown.
  property string storedBatteryMode: Model.BATTERY_SAVER_MODE_DEFAULT
  // A tab asked for this opening only (the bar's microphone glyph asks for
  // "mic"): shown without being stored; "" once the panel closes, which
  // brings back the tab shown before it (tabBeforeRequest) unless the user
  // chose another one meanwhile.
  property string requestedTab: ""
  property string tabBeforeRequest: ""
  property bool ready: false
  // The card's room for this content on the screen (the popup's available
  // height less its padding); 0: unknown, no cap. Bounds the settings area.
  property real contentRoom: 0

  signal closeRequested()
  signal switchRequested(int direction)
  // A user's change of a panel preference: { previewEnabled },
  // { previewFps }, { panelTab } or { batterySaverMode }. Only togglePreview,
  // chooseFps, chooseTab, toggleBatterySaver and chooseBatteryMode emit it.
  signal settingsRequested(var values)
  // The setup dialog, opened at the config row of key `focus`.
  signal setupRequested(string focus)

  readonly property Item keyCatcher: catcher
  readonly property var record: Daemon.record
  readonly property bool available: Model.available(record)
  readonly property var visual: Model.visualFor(Model.visualKey(record))
  readonly property var message: Model.unavailableMessage(record)
  // The last command failure; a path it ends on is drawn on a line of its own.
  readonly property var commandErrorParts: Model.commandErrorParts(Daemon.commandError)
  readonly property var statsRows: Model.statsRows(record)
  readonly property var statusRows: Model.statusRows(record)
  readonly property var cameras: record.cameras
  readonly property string heroMeta: Model.heroMeta(record)
  readonly property string truncation: Model.truncationText(record)
  // The background effect's choice row, from the settings schema.
  readonly property var effectMode: Model.effectModeView(record, Daemon.settingDrafts)
  readonly property var effectRows: Model.effectRows(record)
  // The Background row (interface revision 15): the image in force and the
  // gallery's two actions, faded while their tool is not on PATH.
  readonly property var backgroundRow: Model.backgroundRowView(record, Daemon.mediaTools, Daemon.mediaBusy, Daemon.backgroundMedia)
  // The Away image row and its Setup... button (interface revision 17).
  readonly property bool awayShown: Model.placeholderSupported(record)
  readonly property var preview: Preview.placeholder
  readonly property bool previewControls: Model.previewControlsShown(record, Preview.pathReason)
  readonly property var fpsOptions: Model.fpsOptions(Preview.fps)
  // The settings group open: this panel's choice of the session (memory
  // only): a group id, "" for none, null for the default (Model.openGroupId).
  property var settingsOpen: null
  // The camera settings exactly as drawn (and as the cursor walks them).
  readonly property var settingsView: Model.settingsView(record, settingsOpen, Daemon.settingDrafts)
  // The Effect tab's generic rows: the daemon's global settings (all but the
  // effect choice, which has a row of its own).
  readonly property var effectSettings: Model.effectSettingsView(record, Daemon.settingDrafts)
  readonly property bool genericEffect: Model.effectSettingsShown(effectSettings)
  // The Battery saver switch (interface revision 22), from the daemon's
  // config row (the panel holds the configuration read while it is open,
  // Daemon.holdConfig), and its Mode dropdown. `batteryMode` is the mode
  // this session last turned off or chose in the dropdown, which the switch
  // turns on again (and the dropdown shows while the saver is off); "" until
  // one was, when the stored mode (storedBatteryMode) is the one.
  property string batteryMode: ""
  readonly property var batterySaver: Model.batterySaverView(record, Daemon.setup.config,
    batteryMode !== "" ? batteryMode : storedBatteryMode)
  // The switch was used since the panel opened: only then is the last
  // setup write's failure shown under it.
  property bool batteryWritten: false
  readonly property real greyedOpacity: 0.45
  // The Mic tab: the microphone's own part, then its settings (the groups
  // of surface "mic"), drawn generically.
  readonly property var micView: Model.micView(record)
  readonly property var micSettings: Model.micSettingsView(record, Daemon.settingDrafts)
  // The Camera tab's health part (interface revision 20): only for the
  // active camera, as the daemon last reported it (Model.healthView).
  // Its suggestions and recommended changes open or fold on their lines:
  // this panel's choice of the session (memory only), for one camera
  // (Model.healthOpenAfter); null: both folded.
  property var healthOpen: null
  readonly property var health: Model.healthView(record, healthOpen)
  readonly property bool recommendedShown: Model.recommendedShown(health)
  // What the keyboard walks and the rows act on: the tab shown's section.
  readonly property var activeView: tab === "effect" ? effectSettings : (tab === "mic" ? micSettings : settingsView)
  readonly property SettingsView activeBlock: tab === "effect" ? effectSettingsBlock : (tab === "mic" ? micSettingsBlock : settingsBlock)
  // A slider is held: the Flickables must not take the drag over.
  property int slidersHeld: 0

  // ---- the tab shown ----------------------------------------------------------
  // Always a word of Model.PANEL_TABS (showTab validates it).
  property string tab: Model.PANEL_TAB_DEFAULT
  readonly property var tabOptions: Model.panelTabOptions(tab, health)

  // ---- the keyboard cursor (one list of stops; see Model.cursorStops) ------
  // Built from the rendered row count, so the cursor and the rows agree.
  readonly property var stops: Model.cursorStops(record, cameraRepeater.count, previewControls, tab, settingsView, effectSettings, micSettings, health, batterySaver)
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var currentStop: cursorActive && stops.length > 0
    ? stops[Model.clampCursor(cursorIndex, stops.length)] : null
  // The effect choice under the cursor while the effect row holds it.
  property int effectCursor: 0
  // The Background row's button under the cursor: 0 Gallery..., 1 Add....
  property int backgroundCursor: 0
  // The frame-rate choice under the cursor while the frame-rate row holds it.
  property int fpsCursor: 0
  // The tab under the cursor while the tab row holds it.
  property int tabCursor: 0
  // The choice under the cursor while a setting's row of buttons holds it.
  property int choiceCursor: -1

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 1.8)
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color hoverFill: Style.hoverFillFor(foreground, accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color glyphColor: visual.colorRole === "urgent" ? urgent
    : (visual.colorRole === "accent" ? accent : foreground)

  implicitHeight: column.implicitHeight

  function hasCursor(kind, index) {
    return currentStop !== null && currentStop.kind === kind
      && (!Model.stopHasIndex(kind) || currentStop.index === index)
  }

  function setCursor(kind, index) {
    var i = Model.stopIndex(stops, kind, index)
    if (i < 0) return
    var moved = !cursorActive || Model.clampCursor(cursorIndex, stops.length) !== i
    cursorActive = true
    cursorIndex = i
    if (moved) landOnSetting()
  }

  // Arriving on a setting's row of buttons lands on its current choice, as
  // on the effect and frame-rate rows.
  function landOnSetting() {
    var stop = currentStop
    var row = stop && stop.kind === "setting" ? Model.viewRow(root.activeView, stop.index) : null
    choiceCursor = row && row.widget === "segmented" ? Model.choiceCursorStart(row) : -1
  }

  // The mouse is over chip `index` of the row at stop `stop`.
  function setChoiceCursor(stop, index) {
    setCursor("setting", stop)
    var row = Model.viewRow(root.activeView, stop)
    if (row && row.widget === "segmented" && index >= 0 && index < row.options.length) choiceCursor = index
  }

  // The effect row takes the cursor on the choice under the mouse.
  function setEffectCursor(index) {
    effectCursor = Model.clampCursor(index, root.effectMode.options.length)
    setCursor("effect", -1)
  }

  // The Background row takes the cursor on the button under the mouse.
  function setBackgroundCursor(index) {
    backgroundCursor = Model.clampCursor(index, root.backgroundRow.buttons.length)
    setCursor("background", -1)
  }

  function setFpsCursor(index) {
    fpsCursor = Model.clampCursor(index, Model.PREVIEW_FPS_CHOICES.length)
    setCursor("fps", -1)
  }

  // Hovering a tab moves the cursor there; it does not change the tab.
  function setTabCursor(index) {
    tabCursor = Model.clampCursor(index, Model.PANEL_TABS.length)
    setCursor("tabs", -1)
  }

  function moveCursor(dy) {
    if (stops.length === 0 || dy === 0) return
    cursorActive = true
    cursorIndex = Model.clampCursor(Model.clampCursor(cursorIndex, stops.length) + (dy > 0 ? 1 : -1), stops.length)
    // Arriving on the effect, frame-rate or tab row lands on the current
    // choice, as the shell's button groups do.
    if (currentStop && currentStop.kind === "effect")
      effectCursor = Math.max(0, Model.effectModeSelected(root.effectMode))
    if (currentStop && currentStop.kind === "fps")
      fpsCursor = Math.max(0, Model.PREVIEW_FPS_CHOICES.indexOf(Preview.fps))
    if (currentStop && currentStop.kind === "tabs")
      tabCursor = Math.max(0, Model.PANEL_TABS.indexOf(tab))
    landOnSetting()
    scrollCursorIntoView()
  }

  // Left/Right: the effect, frame-rate and a setting's choices lay out
  // horizontally (the cursor walks them; Enter or Space chooses), a slider
  // moves, a group header opens (Right) or closes (Left), and the tab row
  // changes the tab at once (a tab runs nothing, so there is nothing to
  // confirm). A dropdown row takes no Left/Right: Enter opens its list.
  function moveCursorH(dx) {
    if (dx === 0 || !currentStop) return
    if (currentStop.kind === "setting")
      moveSettingH(currentStop.index, dx)
    else if (currentStop.kind === "group")
      setGroupOpen(currentStop.index, dx > 0)
    else if (currentStop.kind === "effect")
      effectCursor = Model.clampCursor(effectCursor + (dx > 0 ? 1 : -1), root.effectMode.options.length)
    else if (currentStop.kind === "background")
      backgroundCursor = Model.clampCursor(backgroundCursor + (dx > 0 ? 1 : -1), root.backgroundRow.buttons.length)
    else if (currentStop.kind === "fps")
      fpsCursor = Model.clampCursor(fpsCursor + (dx > 0 ? 1 : -1), Model.PREVIEW_FPS_CHOICES.length)
    else if (currentStop.kind === "tabs")
      chooseTab(Model.clampCursor(tabCursor + (dx > 0 ? 1 : -1), Model.PANEL_TABS.length))
  }

  // The preview's preferences, written only here, on a user's action. The
  // value sent is the flip of the switch in force, or a word of
  // Model.PREVIEW_FPS_CHOICES; Model.settingsEntry checks both again.
  function togglePreview() {
    if (!root.previewControls) return false
    root.settingsRequested({ previewEnabled: !Preview.switchOn })
    return true
  }

  function chooseFps(index) {
    var option = root.fpsOptions[index]
    if (!option || option.selected || !root.previewControls) return false
    root.settingsRequested({ previewFps: option.value })
    return true
  }

  // Shows a tab without writing anything: the stored tab when it changes,
  // and the first one shown. Anything that is not a word of
  // Model.PANEL_TABS shows the default. A cursor inside the old tab's rows
  // moves to the tab row (those rows are gone).
  function showTab(value) {
    var next = Model.panelTabValue(value)
    if (next === root.tab) return
    var inTab = root.currentStop !== null
      && ["switch", "preview", "fps", "tabs"].indexOf(root.currentStop.kind) < 0
    root.tab = next
    root.tabCursor = Model.PANEL_TABS.indexOf(next)
    if (inTab) root.setCursor("tabs", -1)
  }

  // A user's choice of tab: shown at once, then written as a preference.
  // The value sent is a word of Model.PANEL_TABS; Model.settingsEntry checks
  // it again. Nothing while the daemon is unavailable (no tab is drawn), and
  // nothing for the tab already shown.
  function chooseTab(index) {
    var value = Model.PANEL_TABS[index]
    if (value === undefined || !root.available) return false
    root.tabCursor = index
    if (value === root.tab) return false
    root.tabBeforeRequest = ""
    root.showTab(value)
    root.settingsRequested({ panelTab: value })
    return true
  }

  // A choice of the background effect: written as its setting is, at once
  // (Daemon.commitSetting checks it against the row: enabled, and one of
  // its options). Nothing for the choice already made, or while the daemon
  // greys the row out.
  function chooseEffect(index) {
    var row = root.effectMode
    var option = row.options[index]
    if (!option || option.selected || !row.enabled || !root.available) return false
    return Daemon.commitSetting(row.id, option.value)
  }

  // A button of the Background row: Gallery... (0) or Add... (1). Each
  // closes the panel and hands the screen to a tool of the shell (the image
  // picker, the file chooser); the Daemon runs the rest. Nothing while its
  // tool is not on PATH or a flow already runs.
  function activateBackground(index) {
    var button = root.backgroundRow.buttons[index]
    if (!root.backgroundRow.visible || !button || !button.enabled || !root.available) return false
    return index === 0 ? Daemon.openGallery() : Daemon.addBackground()
  }

  // Setup... on the Away image row: the setup dialog, at that row (the panel
  // closes, as for the right click).
  function openAwayImage() {
    if (!root.awayShown || !root.available) return false
    root.setupRequested(Model.AWAY_IMAGE_KEY)
    return true
  }

  // Left/Right on a setting: a row of buttons walks its chip cursor (no
  // write), a slider moves (nudgeSetting).
  function moveSettingH(stop, dx) {
    var row = Model.viewRow(root.activeView, stop)
    if (!row || !row.enabled || !root.available) return false
    if (row.widget === "segmented") {
      root.choiceCursor = Model.choiceCursorAfter(row, root.choiceCursor, dx)
      return true
    }
    return row.widget === "slider" && nudgeSetting(stop, dx)
  }

  // A key moves the slider at keyboard stop `stop` by about a twentieth of
  // its range, from the value it shows; written as a slider move is
  // (Daemon.moveSetting: a draft, then the debounce). Nothing for a greyed
  // row.
  function nudgeSetting(stop, dx) {
    var row = Model.viewRow(root.activeView, stop)
    if (!row || !row.enabled || !root.available) return false
    var value = Model.settingNudge(row, row.value, dx > 0 ? 1 : -1)
    return value !== null && Daemon.moveSetting(row.id, value)
  }

  // Enter or Space on a setting: the choice under the chip cursor is made, a
  // dropdown opens its list, a switch flips, an action runs (a slider moves
  // with Left/Right). Nothing for a greyed row, or the choice already made.
  function activateSetting(stop) {
    var row = Model.viewRow(root.activeView, stop)
    if (!row || !row.enabled || !root.available) return false
    if (row.widget === "segmented") {
      var option = row.options[root.choiceCursor]
      return !!option && option.value !== row.value && Daemon.commitSetting(row.id, option.value)
    }
    if (row.widget === "dropdown") return root.activeBlock.openChoices(stop)
    if (row.widget === "switch") return Daemon.commitSetting(row.id, row.value !== true)
    if (row.widget === "action") return Daemon.runSettingAction(row.id)
    return false
  }

  // A group of the view opened or closed, by its place in the view: one is
  // open at a time (Model.groupOpenAfter). A cursor on its header stays on
  // it, though the rows of the group closed above it are gone.
  function setGroupOpen(index, open) {
    var group = root.settingsView.groups[index]
    if (!group || group.expanded === open) return
    var onHeader = hasCursor("group", index)
    root.settingsOpen = Model.groupOpenAfter(root.settingsOpen, root.record.settings, group.id, open)
    if (onHeader) setCursor("group", index)
    scrollItemIntoView(settingsBlock.groupItem(index), true)
  }

  function toggleGroup(id) {
    var groups = root.settingsView.groups
    for (var i = 0; i < groups.length; i++) if (groups[i].id === id) return setGroupOpen(i, !groups[i].expanded)
  }

  // A suggestion's button: its setting written as a switch or a choice is
  // (Daemon.commitSetting checks it against the row again). The suggestion
  // goes when the daemon's next camera_health line leaves it out.
  function applySuggestion(index) {
    var s = root.health.suggestions[index]
    if (!root.available || !s) return false
    return Daemon.commitSetting(s.setting, s.value)
  }

  // Open or fold the suggestions past the first ("suggestions") or the
  // recommended changes ("changes"). Nothing is written.
  function toggleHealthList(which) {
    root.healthOpen = Model.healthOpenAfter(root.healthOpen, root.health, which)
  }

  // Use recommended settings, for the camera whose changes are listed.
  function applyRecommended() {
    if (!root.available || !root.recommendedShown) return false
    return Daemon.applyRecommended()
  }

  // Queued behind a running command rather than refused: it replaces the
  // setting writes still to run (Model.enqueueIntent).
  function resetSettings() {
    if (!root.available || !root.settingsView.reset) return false
    return Daemon.resetSettings()
  }

  // Same rule as the bar's middle click: no toggle while an on/off or other
  // non-setting command's result is still to come (ToggleSwitch's `busy`
  // swallows the click the same way); camera setting writes and the setup
  // dialog's writes never hold it.
  function toggleSwitch() {
    if (!root.available || Daemon.toggleBusy) return false
    return Daemon.setEnabled(!root.record.enabled)
  }

  // The microphone's own switch: `mic on` or `mic off`, by what the daemon
  // reports. Nothing while its last on/off is still to come (Daemon.micBusy).
  function toggleMic() {
    if (!root.available || !root.micView.visible || Daemon.micBusy) return false
    return Daemon.setMicHost(!root.micView.hostOn)
  }

  // The Battery saver switch: writes `off` while the saver is on, else the
  // last mode that was not `off` (`config set -- video.battery_saver MODE`,
  // through the daemon's setup writes). Turning it off first remembers the
  // mode in force, for the next time it is turned on. Nothing while the row
  // is greyed by the daemon or a write is running.
  function toggleBatterySaver() {
    var view = root.batterySaver
    if (!root.available || !view.visible || view.mode === null) return false
    var memory = view.on ? Model.batterySaverMemory(Daemon.setup.config, root.record) : null
    if (!Daemon.setConfig(Model.BATTERY_SAVER_KEY, view.mode)) return false
    root.batteryWritten = true
    if (memory !== null) {
      root.batteryMode = memory
      if (memory !== root.storedBatteryMode) root.settingsRequested({ batterySaverMode: memory })
    }
    return true
  }

  // A choice of the Mode dropdown (Model.batterySaverModeChoice: one of its
  // choices, not the one shown, while it takes one). While the saver is on
  // it is written to the daemon at once (`config set -- video.battery_saver
  // MODE`, through the daemon's setup writes); either way it becomes the
  // remembered mode, the one the switch turns on next, stored in the
  // settings when it differs from the stored one. Nothing while the row is
  // greyed, the mode in force is read-only, or a setup write is running.
  function chooseBatteryMode(value) {
    var view = root.batterySaver
    var word = Model.batterySaverModeChoice(view, value)
    if (!root.available || word === null || Daemon.setupBusy) return false
    if (view.on) {
      if (!Daemon.setConfig(Model.BATTERY_SAVER_KEY, word)) return false
      root.batteryWritten = true
    }
    root.batteryMode = word
    if (word !== root.storedBatteryMode) root.settingsRequested({ batterySaverMode: word })
    return true
  }

  // Enter or Space on the Mode dropdown: its list opens and takes the
  // keyboard (the shell Dropdown's own keys: Up/Down or j/k walk, Enter
  // chooses, Escape closes); the key catcher gets it back on close. Nothing
  // while it takes no choice (greyed, a read-only mode in force, or a setup
  // write running).
  function openBatteryModes() {
    if (!root.available || !root.batterySaver.visible || !batteryModeBox.takesChoice) return false
    batteryModeList.open()
    return true
  }

  // The panel reads the configuration while it is open, for the switch.
  function syncConfigHold() {
    if (root.opened) Daemon.holdConfig(root)
    else Daemon.releaseConfig(root)
  }

  function activateCursor() {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "switch") toggleSwitch()
    else if (stop.kind === "mic-host") toggleMic()
    else if (stop.kind === "battery") toggleBatterySaver()
    else if (stop.kind === "battery-mode") openBatteryModes()
    else if (stop.kind === "preview") togglePreview()
    else if (stop.kind === "fps") chooseFps(fpsCursor)
    else if (stop.kind === "tabs") chooseTab(tabCursor)
    else if (stop.kind === "effect") chooseEffect(effectCursor)
    else if (stop.kind === "background") activateBackground(backgroundCursor)
    else if (stop.kind === "away") openAwayImage()
    else if (stop.kind === "reset") resetSettings()
    else if (stop.kind === "suggestion") applySuggestion(stop.index)
    else if (stop.kind === "recommended") applyRecommended()
    else if (stop.kind === "suggestions-more") toggleHealthList("suggestions")
    else if (stop.kind === "recommended-changes") toggleHealthList("changes")
    else if (stop.kind === "group") setGroupOpen(stop.index, !(root.settingsView.groups[stop.index] || {}).expanded)
    else if (stop.kind === "setting") activateSetting(stop.index)
    else if (stop.kind === "camera") {
      var row = cameraRepeater.itemAt(stop.index)
      if (row) row.choose()
    } else if (stop.kind === "next") Daemon.nextCamera()
  }

  // Only does anything when the screen is too short for the card (the
  // Flickable then scrolls); at the normal size everything is in view. A
  // settings row or header is first brought into view in the settings'
  // own Flickable, then that area in the panel's.
  function scrollItemIntoView(item, inner) {
    if (!item) return
    Qt.callLater(function() {
      if (!item) return
      if (inner === true) scrollWithin(root.activeBlock.flick, item)
      scrollWithin(flick, inner === true ? root.activeBlock.flick : item)
    })
  }

  function scrollWithin(f, item) {
    var margin = Style.space(6)
    var top = item.mapToItem(f.contentItem, 0, 0).y
    var bottom = top + item.height
    var maxY = Math.max(0, f.contentHeight - f.height)
    if (top < f.contentY + margin) f.contentY = Math.max(0, top - margin)
    else if (bottom > f.contentY + f.height - margin)
      f.contentY = Math.min(maxY, bottom + margin - f.height)
  }

  function scrollCursorIntoView() {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "switch") flick.contentY = 0
    else if (stop.kind === "preview") scrollItemIntoView(previewLine)
    else if (stop.kind === "fps") scrollItemIntoView(fpsLine)
    else if (stop.kind === "tabs") scrollItemIntoView(tabRow)
    else if (stop.kind === "group") scrollItemIntoView(settingsBlock.groupItem(stop.index), true)
    else if (stop.kind === "setting") scrollItemIntoView(root.activeBlock.rowItem(stop.index), true)
    else if (stop.kind === "reset") scrollItemIntoView(settingsBlock.resetItem)
    else if (stop.kind === "suggestion") scrollItemIntoView(suggestionRepeater.itemAt(stop.index))
    else if (stop.kind === "recommended") scrollItemIntoView(recommendedButton)
    else if (stop.kind === "suggestions-more") scrollItemIntoView(suggestionsMore)
    else if (stop.kind === "recommended-changes") scrollItemIntoView(recommendedChangesLine)
    else if (stop.kind === "effect") scrollItemIntoView(effectChoices)
    else if (stop.kind === "background") scrollItemIntoView(backgroundLine)
    else if (stop.kind === "away") scrollItemIntoView(awayLine)
    else if (stop.kind === "battery") scrollItemIntoView(batteryBlock)
    else if (stop.kind === "battery-mode") scrollItemIntoView(batteryModeLine)
    else if (stop.kind === "mic-host") scrollItemIntoView(micHostLine)
    else if (stop.kind === "camera") scrollItemIntoView(cameraRepeater.itemAt(stop.index))
    else scrollItemIntoView(nextButton)
  }

  onOpenedChanged: {
    syncConfigHold()
    batteryWritten = false
    if (opened) {
      cursorActive = false
      cursorIndex = 0
      flick.contentY = 0
    }
  }
  onStopsChanged: if (cursorIndex >= stops.length) cursorIndex = Math.max(0, stops.length - 1)
  onStoredTabChanged: showTab(storedTab)
  onRequestedTabChanged: {
    if (requestedTab !== "") {
      if (tabBeforeRequest === "") tabBeforeRequest = ready ? tab : Model.panelTabValue(storedTab)
      showTab(requestedTab)
    } else {
      var back = tabBeforeRequest
      tabBeforeRequest = ""
      if (back !== "") showTab(back)
    }
  }
  Component.onDestruction: Daemon.releaseConfig(root)
  Component.onCompleted: {
    syncConfigHold()
    showTab(storedTab)
    if (requestedTab !== "") {
      tabBeforeRequest = tab
      showTab(requestedTab)
    }
    ready = true
  }

  // A label and a value on one line, the value right-aligned and elided.
  component InfoRow: Item {
    id: infoRow
    property string label: ""
    property string value: ""
    property color valueColor: root.foreground
    property int valueElide: Text.ElideRight
    width: parent ? parent.width : 0
    implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

    Text {
      id: infoLabel
      textFormat: Text.PlainText
      text: infoRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      id: infoValue
      textFormat: Text.PlainText
      anchors.right: parent.right
      width: Math.max(0, parent.width - infoLabel.implicitWidth - Style.space(12))
      horizontalAlignment: Text.AlignRight
      elide: infoRow.valueElide
      text: infoRow.value
      color: infoRow.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  PanelKeyCatcher {
    id: catcher
    anchors.fill: parent
    onMoveRequested: function(dx, dy) {
      // The first key only shows the cursor, as in the shell's panels.
      if (!root.cursorActive) {
        if (root.stops.length > 0) root.cursorActive = true
        return
      }
      if (dy !== 0) root.moveCursor(dy)
      else root.moveCursorH(dx)
    }
    onActivateRequested: if (root.cursorActive) root.activateCursor()
    onCloseRequested: root.closeRequested()
    onTabRequested: function(direction) { root.switchRequested(direction) }
    // 1, 2, 3: a tab by its place in the row, as the shell's agents panel
    // jumps to an account by its number.
    onTextKey: function(t) {
      var n = Model.PANEL_TABS.length
      if (t.length === 1 && t >= "1" && t <= String(n)) root.chooseTab(Number(t) - 1)
    }

    // The scroll fallback: at the normal size the card is as tall as the
    // content and this never moves; on a screen too short for the card it
    // scrolls, and only then.
    Flickable {
      id: flick
      objectName: "panelFlick"
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height + 0.5 && root.slidersHeld === 0
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      // Inset from the clipped edges, so a row's border is never shaved.
      Column {
        id: column
        x: Style.space(2)
        width: flick.width - Style.space(4)
        spacing: Style.space(12)

        // ---- header: glyph, title, status line, switch
        PanelHero {
          id: hero
          objectName: "hero"
          width: parent.width
          title: Model.PRODUCT
          meta: root.heroMeta
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.visual.dimmed ? 0.5 : 1.0
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.visual.glyph
              color: root.glyphColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              id: toggle
              objectName: "enableSwitch"
              visible: root.available
              checked: root.record.enabled
              busy: Daemon.toggleBusy
              hasCursor: root.hasCursor("switch", -1)
              foreground: root.foreground
              accent: root.accent
              onHovered: function(on) { if (on) root.setCursor("switch", -1) }
              onToggled: root.toggleSwitch()
              Accessible.role: Accessible.CheckBox
              Accessible.name: "Camera"
              Accessible.checkable: true
              Accessible.checked: root.record.enabled

              PanelToolTip {
                visible: toggle.containsMouse
                text: root.record.enabled ? "Turn the camera off" : "Turn the camera on"
                fontFamily: root.fontFamily
              }
            }
          }
        }

        // ---- daemon unavailable
        Column {
          objectName: "unavailableBlock"
          width: parent.width
          spacing: Style.space(6)
          visible: !root.available

          Text {
            objectName: "unavailableTitle"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            text: root.message.title
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          // A file path the title ends on, on a line of its own. It wraps at
          // any character, without preferring a "/": the break falls wherever
          // the line is full, so the path reads as one string that ran on.
          Text {
            objectName: "unavailablePath"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WrapAnywhere
            visible: text !== ""
            text: root.message.path
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            text: root.message.detail
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            objectName: "unavailableHint"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            text: root.message.hint
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          // Shown, never run: the plugin has no button that starts the daemon.
          Text {
            objectName: "unavailableCommand"
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            visible: text !== ""
            text: root.message.commandText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- the daemon's error text, whatever the state
        Text {
          objectName: "daemonError"
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          visible: root.available && root.record.error !== ""
          text: root.record.error
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---- the daemon's warning (it keeps streaming): the normal text
        // colour behind a caution sign, never the urgent colour
        Text {
          objectName: "daemonWarning"
          Accessible.role: Accessible.StaticText
          Accessible.name: "Warning: " + root.record.warning
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          visible: root.available && root.record.warning !== ""
          text: Model.GLYPH_WARNING + " " + root.record.warning
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---- the last control command's failure; its text and the path it
        // may end on read as one message, so they sit close together
        Column {
          objectName: "commandErrorBlock"
          width: parent.width
          spacing: Style.space(6)
          visible: root.commandErrorParts.text !== ""

          Text {
            objectName: "commandError"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            text: root.commandErrorParts.text
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          // The path a CLI-missing failure ends on (same reasoning as above).
          Text {
            objectName: "commandErrorPath"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WrapAnywhere
            visible: text !== ""
            text: root.commandErrorParts.path
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- live preview: what apps receive, fixed under the header (an
        // error stays right under the on/off switch, above it). The 16:9
        // area is always drawn while the daemon is available, so the card
        // keeps its size whether a frame, the starting box or a note shows.
        Column {
          id: previewBlock
          objectName: "previewBlock"
          width: parent.width
          spacing: Style.space(8)
          visible: root.preview.mode !== "hidden"

          // 16:9, as the frames are (480x270). The theme's fill for a note
          // and while the preview starts; black only behind a frame.
          Rectangle {
            id: previewFrame
            objectName: "previewFrame"
            width: parent.width
            height: Math.round(width * 9 / 16)
            color: root.preview.mode === "image" ? "black" : root.hoverFill
            border.width: 1
            border.color: root.faint
            clip: true
            Accessible.role: Accessible.Graphic
            Accessible.name: root.preview.mode === "image" ? "Camera preview" : root.preview.text

            // The source is built from the validated path only (see
            // Model.previewSource); a new frame is a new URL, never cached.
            // Loaded off the UI thread, and the last frame stays up while the
            // next one loads, so a reload does not flash the black fill. Bound
            // only while this panel is open: a closed panel (its content is
            // kept once built) loads nothing while another one previews.
            // Decoded at most at the frame size, whatever the file holds.
            Image {
              id: previewImage
              objectName: "previewImage"
              anchors.fill: parent
              anchors.margins: 1
              fillMode: Image.PreserveAspectCrop
              cache: false
              asynchronous: true
              retainWhileLoading: true
              sourceSize.width: 480
              sourceSize.height: 270
              visible: root.opened && root.preview.mode === "image"
              source: root.opened && root.preview.mode === "image" ? Preview.frameSource : ""
            }
            // While the preview starts.
            Text {
              objectName: "previewPlaceholder"
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              visible: root.preview.mode === "box"
              text: root.preview.mode === "box" ? root.preview.text : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            // Wherever no frame is shown and none is starting: the preview
            // cannot work here (a daemon before revision 5, an unusable
            // XDG_RUNTIME_DIR), it ended with an error, or the camera is off
            // or idle, or the preview is off.
            Text {
              objectName: "previewNote"
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              visible: root.preview.mode === "note"
              text: root.preview.mode === "note" ? root.preview.text : ""
              color: root.preview.error ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // The Preview switch on the left, the rate on the right: one row.
          Item {
            objectName: "previewControls"
            width: parent.width
            visible: root.previewControls
            implicitHeight: Math.max(previewLine.implicitHeight, fpsLine.implicitHeight)

            Item {
              id: previewLine
              objectName: "previewRow"
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              visible: root.previewControls
              implicitWidth: previewLabel.implicitWidth + Style.space(10) + previewSwitch.implicitWidth
              implicitHeight: Math.max(previewLabel.implicitHeight, previewSwitch.implicitHeight)
              width: implicitWidth
              height: implicitHeight

              Text {
                id: previewLabel
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Preview"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              ToggleSwitch {
                id: previewSwitch
                objectName: "previewToggle"
                anchors.left: previewLabel.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                checked: Preview.switchOn
                hasCursor: root.hasCursor("preview", -1)
                foreground: root.foreground
                accent: root.accent
                onHovered: function(on) { if (on) root.setCursor("preview", -1) }
                onToggled: root.togglePreview()
                Accessible.role: Accessible.CheckBox
                Accessible.name: "Preview"
                Accessible.description: "When on, opening the panel starts the camera for the preview"
                Accessible.checkable: true
                Accessible.checked: Preview.switchOn

                // What the switch decides (R1): whether opening the panel
                // starts the camera. Frames of a camera another app uses show
                // either way.
                PanelToolTip {
                  visible: previewSwitch.containsMouse
                  text: Preview.switchOn ? "Preview only while another app uses the camera"
                    : "Start the camera for the preview whenever the panel opens"
                  fontFamily: root.fontFamily
                }
              }
            }

            // The rate the preview asks for: one stop, Left/Right walk it. The
            // shell's ButtonGroup, driven by the panel cursor (cursorIndex and
            // hovered), never by Tab focus.
            Item {
              id: fpsLine
              objectName: "fpsRow"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.previewControls
              implicitWidth: fpsChoices.implicitWidth
              implicitHeight: fpsChoices.implicitHeight
              width: implicitWidth
              height: implicitHeight

              ButtonGroup {
                id: fpsChoices
                objectName: "fpsChoices"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                options: root.fpsOptions
                value: String(Preview.fps)
                focusable: false
                cursorIndex: root.hasCursor("fps", -1) ? root.fpsCursor : -1
                foreground: root.foreground
                background: Commons.Color.background
                accent: root.accent
                fontFamily: root.fontFamily
                onHovered: function(index, isHovered) { if (isHovered) root.setFpsCursor(index) }
                onChanged: function(value) { root.chooseFps(Model.PREVIEW_FPS_CHOICES.indexOf(Number(value))) }
              }
            }
          }

          // A choice the shell did not store: it holds until the shell is
          // restarted, and nothing else says so.
          Text {
            objectName: "previewUnsaved"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: root.previewControls && Preview.unsaved
            text: Model.PREVIEW_UNSAVED_TEXT
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- the tabs: a row of the shell's Buttons (the chips its
        // ButtonGroup draws, as the effect row is), one stop for the panel
        // cursor, then the tab shown. Only while the daemon is available.
        Column {
          id: tabBlock
          objectName: "tabBlock"
          width: parent.width
          spacing: Style.space(12)
          visible: root.available

          Row {
            id: tabRow
            objectName: "tabRow"
            width: parent.width
            spacing: Style.spacing.md
            Accessible.role: Accessible.PageTabList
            Accessible.name: "Panel sections"

            Repeater {
              id: tabRepeater
              objectName: "tabRepeater"
              model: root.tabOptions
              delegate: Button {
                id: tabChip
                required property var modelData
                required property int index
                objectName: "tab-" + modelData.value
                width: (tabRow.width - tabRow.spacing * (Model.PANEL_TABS.length - 1)) / Model.PANEL_TABS.length
                text: modelData.label
                // The Camera tab's caution sign while the camera has a warning,
                // at the label's size so the chip keeps the row's height.
                iconText: modelData.glyph
                iconSize: fontSize
                tooltipText: modelData.description + " (" + (index + 1) + ")"
                selected: modelData.selected
                // One highlight: the panel cursor, which the mouse moves too.
                hasCursor: root.hasCursor("tabs", -1) && root.tabCursor === index
                bordered: true
                foreground: root.foreground
                // The fill the shell's ButtonGroup gives its chips.
                background: Commons.Color.background
                accent: root.accent
                fontFamily: root.fontFamily
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.name
                Accessible.description: modelData.description
                Accessible.selectable: true
                Accessible.selected: modelData.selected
                onHovered: function(on) { if (on) root.setTabCursor(tabChip.index) }
                onClicked: root.chooseTab(tabChip.index)
              }
            }
          }

          // ---- Effect: the background effect's choices, the image the
          // daemon holds, then the other global settings
          Column {
            id: effectTab
            objectName: "effectTab"
            width: parent.width
            spacing: Style.space(10)
            visible: root.tab === "effect"

            Flow {
              id: effectChoices
              objectName: "effectChoices"
              width: parent.width
              spacing: Style.spacing.md
              visible: root.effectMode.visible

              Repeater {
                id: effectRepeater
                objectName: "effectRepeater"
                model: root.effectMode.options
                delegate: Button {
                  id: effectChip
                  required property var modelData
                  required property int index
                  objectName: "effectChoice-" + index
                  text: modelData.label
                  tooltipText: modelData.tooltip
                  selected: modelData.selected
                  // One highlight: the panel cursor, which the mouse moves too.
                  hasCursor: root.hasCursor("effect", -1) && root.effectCursor === index
                  bordered: true
                  // Faded while the daemon greys the setting out; the
                  // reason is the hint below.
                  opacity: modelData.faded ? 0.45 : 1.0
                  foreground: root.foreground
                  // The fill the shell's ButtonGroup gives its chips.
                  background: Commons.Color.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onHovered: function(on) { if (on) root.setEffectCursor(effectChip.index) }
                  onClicked: root.chooseEffect(effectChip.index)
                }
              }
            }

            // ---- the Background row: the image in force (a 16:9
            // thumbnail, decoded at twice its drawn size; a faint image
            // glyph when there is none or it does not load) and its name,
            // then Gallery... and Add...
            Item {
              id: backgroundLine
              objectName: "backgroundLine"
              width: parent.width
              visible: root.backgroundRow.visible
              implicitHeight: visible ? Math.max(backgroundThumb.height, backgroundButtons.implicitHeight, backgroundText.implicitHeight) : 0
              height: implicitHeight

              MediaThumbnail {
                id: backgroundThumb
                objectName: "background"
                anchors.verticalCenter: parent.verticalCenter
                name: "Background image: " + root.backgroundRow.label
                // Only the checked path's URL (Model.mediaImageSource: the
                // image, or a video's poster from the read gallery), and
                // only while the panel is open.
                source: root.opened && root.backgroundRow.visible ? root.backgroundRow.source : ""
                video: root.backgroundRow.video
                fill: root.hoverFill
                faint: root.faint
                fontFamily: root.fontFamily
              }

              Column {
                id: backgroundText
                anchors.left: backgroundThumb.right
                anchors.leftMargin: Style.space(10)
                anchors.right: backgroundButtons.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: Model.BACKGROUND_ROW_LABEL
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  objectName: "backgroundLabel"
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideMiddle
                  text: root.backgroundRow.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Row {
                id: backgroundButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.md

                Repeater {
                  model: root.backgroundRow.buttons.length
                  delegate: Button {
                    id: backgroundButton
                    required property int index
                    readonly property var button: root.backgroundRow.buttons[index]
                    objectName: "backgroundButton-" + index
                    text: button ? button.label : ""
                    tooltipText: button ? button.tooltip : ""
                    hasCursor: root.hasCursor("background", -1) && root.backgroundCursor === index
                    bordered: true
                    // Faded and inert while its tool is not on PATH or a
                    // flow runs (the tooltip and the hint below say why);
                    // kept enabled so the tooltip still shows.
                    opacity: button && button.enabled ? 1.0 : 0.45
                    foreground: root.foreground
                    background: Commons.Color.background
                    accent: root.accent
                    fontFamily: root.fontFamily
                    Accessible.name: button ? button.label : ""
                    Accessible.description: button ? button.tooltip : ""
                    onHovered: function(on) { if (on) root.setBackgroundCursor(backgroundButton.index) }
                    onClicked: root.activateBackground(backgroundButton.index)
                  }
                }
              }
            }

            // What a running flow waits for (the buttons are faded
            // meanwhile), else which of the gallery's tools is not on PATH.
            Text {
              objectName: "backgroundHint"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              visible: text !== ""
              text: Model.backgroundHint(root.backgroundRow, Daemon.mediaFlow)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // ---- the Away image row (interface revision 17): its label,
            // then Setup... on the right. The watch's snapshot carries no
            // config value (no file name here), so the button opens the
            // setup dialog at the Away image row, where it is chosen.
            Item {
              id: awayLine
              objectName: "awayLine"
              width: parent.width
              visible: root.awayShown
              implicitHeight: visible ? Math.max(awayButton.implicitHeight, awayLabel.implicitHeight) : 0
              height: implicitHeight

              Text {
                id: awayLabel
                objectName: "awayLabel"
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: awayButton.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: Model.AWAY_ROW_LABEL
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Button {
                id: awayButton
                objectName: "awayButton"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Model.AWAY_BUTTON_LABEL
                tooltipText: Model.AWAY_BUTTON_TOOLTIP
                hasCursor: root.hasCursor("away", -1)
                bordered: true
                foreground: root.foreground
                background: Commons.Color.background
                accent: root.accent
                fontFamily: root.fontFamily
                Accessible.name: Model.AWAY_ROW_LABEL + ": " + Model.AWAY_BUTTON_LABEL
                Accessible.description: Model.AWAY_BUTTON_TOOLTIP
                onHovered: function(on) { if (on) root.setCursor("away", -1) }
                onClicked: root.openAwayImage()
              }
            }

            // ---- the Battery saver switch (interface revision 22): the
            // daemon's `video.battery_saver`, on while its mode is not off.
            // Under it the Mode row: "Mode" and a dropdown of the modes the
            // switch turns on (Model.batterySaverView's `modes`), showing
            // the daemon's mode while on and the remembered one while off
            // (a mode the plugin does not offer is shown read-only). Then
            // what is in force now (the end of the daemon's description),
            // why it is greyed, and the daemon's notice when the running
            // camera does not match yet.
            Column {
              id: batteryBlock
              objectName: "batteryBlock"
              width: parent.width
              spacing: Style.space(2)
              visible: root.batterySaver.visible

              Item {
                id: batteryLine
                objectName: "batteryRow"
                width: parent.width
                implicitHeight: Math.max(batteryLabel.implicitHeight, batterySwitch.implicitHeight)
                height: implicitHeight

                Text {
                  id: batteryLabel
                  objectName: "batteryLabel"
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: batterySwitch.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: Model.BATTERY_SAVER_LABEL
                  color: root.batterySaver.enabled ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                ToggleSwitch {
                  id: batterySwitch
                  objectName: "batterySwitch"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: root.batterySaver.enabled ? 1.0 : root.greyedOpacity
                  interactive: root.batterySaver.enabled
                  checked: root.batterySaver.on
                  busy: Daemon.setupBusy
                  hasCursor: root.hasCursor("battery", -1)
                  foreground: root.foreground
                  accent: root.accent
                  onHovered: function(on) { if (on) root.setCursor("battery", -1) }
                  onToggled: root.toggleBatterySaver()
                  Accessible.role: Accessible.CheckBox
                  Accessible.name: Model.BATTERY_SAVER_LABEL
                  Accessible.description: root.batterySaver.reason !== "" ? root.batterySaver.reason : root.batterySaver.now
                  Accessible.checkable: true
                  Accessible.checked: root.batterySaver.on

                  PanelToolTip {
                    visible: batterySwitch.containsMouse
                    text: root.batterySaver.reason !== "" ? root.batterySaver.reason
                      : (root.batterySaver.on ? "Turn the battery saver off" : "Turn the battery saver on")
                    fontFamily: root.fontFamily
                  }
                }
              }
              // The Mode row, laid out as the settings' dropdown rows
              // (SettingsView): the label on the left, the shell's Dropdown
              // on the right, as wide as its longest label. Greyed with the
              // switch; a read-only mode is shown at full strength but takes
              // no choice. The Dropdown sets its own value on a choice: it
              // is bound to the view's again, so what the daemon (or the
              // remembered mode) says is what shows.
              Item {
                id: batteryModeLine
                objectName: "batteryModeRow"
                width: parent.width
                implicitHeight: Math.max(batteryModeLabel.implicitHeight, batteryModeBox.implicitHeight)
                height: implicitHeight

                Text {
                  id: batteryModeLabel
                  objectName: "batteryModeLabel"
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: batteryModeBox.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: Model.BATTERY_SAVER_MODE_ROW_LABEL
                  color: root.batterySaver.enabled ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Item {
                  id: batteryModeBox
                  // The dropdown takes a choice: the view says so and no
                  // setup write is running (as the switch shows busy), so a
                  // choice is never dropped silently.
                  readonly property bool takesChoice: root.batterySaver.modeEnabled && !Daemon.setupBusy
                  readonly property var options: root.batterySaver.modeReadOnly
                    ? [{ value: root.batterySaver.modeValue, label: root.batterySaver.modeLabel }] : root.batterySaver.modes
                  // Wide enough for the longest label, never less than 220,
                  // held within the line (as SettingsView's dropdown).
                  readonly property real labelsWidth: widestLabel()
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: Math.max(Style.space(220), labelsWidth + 2 * Style.spacing.controlPaddingX + Style.space(36))
                  implicitHeight: batteryModeList.implicitHeight
                  width: Math.min(implicitWidth, parent.width - Style.space(72))
                  height: implicitHeight

                  // Measured without writing to the metrics (a TextMetrics'
                  // text set inside this binding would loop).
                  FontMetrics {
                    id: batteryModeProbe
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  function widestLabel() {
                    var widest = 0
                    for (var i = 0; i < options.length; i++)
                      widest = Math.max(widest, batteryModeProbe.advanceWidth(options[i].label))
                    return widest
                  }

                  // The Dropdown takes no input while it takes no choice:
                  // hovering it then moves the cursor from here.
                  HoverHandler {
                    enabled: !batteryModeBox.takesChoice
                    onHoveredChanged: if (hovered) root.setCursor("battery-mode", -1)
                  }

                  // A list open when the dropdown stops taking a choice
                  // (greyed, read-only, hidden, a setup write running)
                  // closes, choosing nothing.
                  Connections {
                    target: root
                    function onBatterySaverChanged() { batteryModeBox.closeIfIdle() }
                  }
                  Connections {
                    target: Daemon
                    function onSetupBusyChanged() { batteryModeBox.closeIfIdle() }
                  }
                  function closeIfIdle() {
                    if (batteryModeList.popupOpen && (!root.batterySaver.visible || !takesChoice)) batteryModeList.close()
                  }

                  Dropdown {
                    id: batteryModeList
                    objectName: "batteryModeDropdown"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: batteryModeBox.takesChoice
                    opacity: root.batterySaver.enabled ? 1.0 : root.greyedOpacity
                    showLabel: false
                    options: batteryModeBox.options
                    value: root.batterySaver.modeValue
                    hasCursor: root.hasCursor("battery-mode", -1)
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    Accessible.role: Accessible.ComboBox
                    Accessible.name: Model.BATTERY_SAVER_MODE_NAME
                    Accessible.description: root.batterySaver.reason !== "" ? root.batterySaver.reason : root.batterySaver.modeLabel
                    onHovered: function(isHovered) { if (isHovered) root.setCursor("battery-mode", -1) }
                    onChanged: function(value) {
                      batteryModeList.value = Qt.binding(function() { return root.batterySaver.modeValue })
                      root.chooseBatteryMode(value)
                    }
                    onPopupOpenChanged: if (!popupOpen) catcher.forceActiveFocus()
                  }
                }
              }
              Text {
                objectName: "batteryReason"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.batterySaver.reason
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                objectName: "batteryNow"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== "" && root.batterySaver.enabled
                text: root.batterySaver.now
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                objectName: "batteryNotice"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.batterySaver.notice
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                objectName: "batteryError"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.batteryWritten ? Daemon.setupError : ""
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Repeater {
              model: root.effectRows
              delegate: InfoRow {
                required property var modelData
                label: modelData.label
                value: modelData.value
                // A path keeps its file name in view.
                valueElide: Text.ElideMiddle
              }
            }

            // Why the choices are greyed (the daemon's reason), or why
            // there are none: a daemon below revision 9, an old CLI or
            // plugin, no module with a background effect.
            Text {
              objectName: "effectHint"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              visible: text !== ""
              text: root.effectMode.visible ? root.effectMode.reason : root.effectMode.hint
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // ---- the daemon's other global settings (the effect's strength,
            // noise removal and whatever the modules add), drawn by the same
            // renderer as the camera's; the effect choice above is not among
            // them. None while the daemon publishes none.
            Column {
              id: effectSettingsArea
              objectName: "effectSettingsArea"
              width: parent.width
              spacing: Style.space(10)
              visible: root.genericEffect

              SettingsView {
                id: effectSettingsBlock
                objectName: "effectSettingsView"
                namePrefix: "effect-"
                readonly property real areaTop: tabBlock.y + effectTab.y + effectSettingsArea.y + y
                width: parent.width
                room: root.contentRoom > 0 ? root.contentRoom - areaTop : 0
                bar: root.bar
                view: root.effectSettings
                // Only the tab shown has a cursor (both views number their stops from 0).
                cursorStop: root.tab === "effect" ? root.currentStop : null
                choiceCursor: root.choiceCursor
                keyCatcher: catcher
                slidersHeld: root.slidersHeld
                foreground: root.foreground
                dim: root.dim
                faint: root.faint
                accent: root.accent
                hoverFill: root.hoverFill
                fontFamily: root.fontFamily
                onCursorRequested: function(kind, index) { root.setCursor(kind, index) }
                onChoiceHovered: function(stop, index) { root.setChoiceCursor(stop, index) }
                onHeldChanged: function(delta) { root.slidersHeld = Math.max(0, root.slidersHeld + delta) }
              }
            }
          }

          // ---- Camera: the cameras, then the camera's settings
          Column {
            id: cameraTab
            objectName: "cameraTab"
            width: parent.width
            spacing: Style.space(10)
            visible: root.tab === "camera"

            Column {
              objectName: "camerasBlock"
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "CAMERAS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: root.cameras.length === 0
                text: "No cameras found"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                id: cameraRepeater
                objectName: "cameraRepeater"
                model: root.cameras
                delegate: CursorSurface {
                  id: cameraRow
                  required property var modelData
                  required property int index
                  readonly property bool isActive: Model.isActiveCamera(root.record, modelData)
                  readonly property bool selectable: modelData.selectId !== "" && !isActive
                  width: parent ? parent.width : 0
                  implicitHeight: rowText.implicitHeight + Style.spacing.xl
                  // Visuals from the panel cursor and the active camera only,
                  // never from containsMouse (the CursorSurface contract).
                  hasCursor: root.hasCursor("camera", index)
                  current: isActive
                  foreground: root.foreground
                  fill: root.hoverFill
                  currentFill: root.selectedFill
                  Accessible.role: Accessible.RadioButton
                  Accessible.name: modelData.label
                  Accessible.checkable: true
                  Accessible.checked: isActive

                  function choose() {
                    if (cameraRow.selectable && root.available) return Daemon.selectCamera(cameraRow.modelData.selectId)
                    return false
                  }

                  Text {
                    id: rowMark
                    textFormat: Text.PlainText
                    x: Style.space(6)
                    width: Style.space(22)
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                    text: cameraRow.isActive ? Model.GLYPH_RADIO_ON : Model.GLYPH_RADIO_OFF
                    color: cameraRow.isActive ? root.accent : root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Column {
                    id: rowText
                    anchors.left: rowMark.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: rowUsb.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: cameraRow.modelData.label
                      color: cameraRow.modelData.selectId !== "" || cameraRow.isActive ? root.foreground : root.faint
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: cameraRow.isActive
                    }
                    Text {
                      objectName: "cameraNote"
                      textFormat: Text.PlainText
                      width: parent.width
                      wrapMode: Text.Wrap
                      visible: text !== ""
                      text: cameraRow.modelData.selectNote
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Text {
                    id: rowUsb
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: cameraRow.modelData.usb
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: cameraRow.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: root.setCursor("camera", cameraRow.index)
                    onClicked: cameraRow.choose()
                  }
                }
              }

              Text {
                objectName: "camerasTruncated"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.truncation
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Shown only when there is a camera to move to.
            Button {
              id: nextButton
              objectName: "nextCameraButton"
              visible: Model.canNext(root.record)
              text: "Next camera"
              iconText: Model.GLYPH_NEXT
              bordered: true
              hasCursor: root.hasCursor("next", -1)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              Accessible.role: Accessible.Button
              Accessible.name: "Next camera"
              onHovered: function(on) { if (on) root.setCursor("next", -1) }
              onClicked: Daemon.nextCamera()
            }

            // ---- the active camera's health (interface revision 20): the
            // rate it really delivers when short of its mode's, the daemon's
            // warnings about it (as the daemon's own warning: the normal text
            // colour behind a caution sign), and effect suggestions, each
            // with its button: the first, then a line that opens the rest
            // (Model.healthView folds them, so the settings' groups keep
            // their room). Nothing for another camera, or before the daemon
            // reports it; a button writes only on a click, and what it
            // changed shows when the daemon next reports. Count models, as
            // SettingsView's: a new report changes what a row shows.
            PanelSeparator {
              objectName: "healthSeparator"
              visible: root.health.visible
              foreground: root.foreground
            }

            Column {
              id: healthBlock
              objectName: "healthBlock"
              width: parent.width
              spacing: Style.space(6)
              visible: root.health.visible

              Text {
                objectName: "healthDelivers"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.health.delivers
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                objectName: "healthWarnings"
                model: root.health.warnings.length
                delegate: Text {
                  required property int index
                  readonly property string warning: root.health.warnings[index] || ""
                  objectName: "healthWarning-" + index
                  Accessible.role: Accessible.StaticText
                  Accessible.name: "Warning: " + warning
                  textFormat: Text.PlainText
                  width: parent ? parent.width : 0
                  wrapMode: Text.Wrap
                  text: Model.GLYPH_WARNING + " " + warning
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Repeater {
                id: suggestionRepeater
                objectName: "healthSuggestions"
                model: root.health.shownSuggestions
                delegate: Item {
                  id: suggestionRow
                  required property int index
                  readonly property var suggestion: root.health.suggestions[index] || ({ label: "", reason: "", action: "" })
                  objectName: "healthSuggestion-" + index
                  width: parent ? parent.width : 0
                  implicitHeight: Math.max(suggestionText.implicitHeight, suggestionButton.implicitHeight)
                  height: implicitHeight

                  Column {
                    id: suggestionText
                    anchors.left: parent.left
                    anchors.right: suggestionButton.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      objectName: "healthSuggestionLabel-" + suggestionRow.index
                      textFormat: Text.PlainText
                      width: parent.width
                      wrapMode: Text.Wrap
                      text: suggestionRow.suggestion.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      objectName: "healthSuggestionReason-" + suggestionRow.index
                      textFormat: Text.PlainText
                      width: parent.width
                      wrapMode: Text.Wrap
                      visible: text !== ""
                      text: suggestionRow.suggestion.reason
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  Button {
                    id: suggestionButton
                    objectName: "healthSuggestionButton-" + suggestionRow.index
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: suggestionRow.suggestion.action
                    hasCursor: root.hasCursor("suggestion", suggestionRow.index)
                    bordered: true
                    foreground: root.foreground
                    background: Commons.Color.background
                    accent: root.accent
                    fontFamily: root.fontFamily
                    Accessible.role: Accessible.Button
                    Accessible.name: suggestionRow.suggestion.label + ": " + suggestionRow.suggestion.action
                    Accessible.description: suggestionRow.suggestion.reason
                    onHovered: function(on) { if (on) root.setCursor("suggestion", suggestionRow.index) }
                    onClicked: root.applySuggestion(suggestionRow.index)
                  }
                }
              }

              // "+2 more" / "Fewer suggestions": opens or folds the
              // suggestions past the first, as a settings group's header
              // (the chevron at the right edge).
              CursorSurface {
                id: suggestionsMore
                objectName: "healthSuggestionsMore"
                width: parent.width
                visible: root.health.more.visible
                implicitHeight: suggestionsMoreText.implicitHeight + Style.space(6)
                hasCursor: root.hasCursor("suggestions-more", -1)
                foreground: root.foreground
                fill: root.hoverFill
                Accessible.role: Accessible.Button
                Accessible.name: root.health.more.text
                Accessible.description: root.health.shownSuggestions < root.health.suggestions.length ? "Collapsed" : "Expanded"

                Text {
                  id: suggestionsMoreText
                  objectName: "healthSuggestionsMoreText"
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: suggestionsMoreGlyph.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: root.health.more.text
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  id: suggestionsMoreGlyph
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  width: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: root.health.more.glyph
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setCursor("suggestions-more", -1)
                  onClicked: root.toggleHealthList("suggestions")
                }
              }
            }

            // ---- camera settings: what the daemon publishes for the camera.
            // While the daemon has the camera open (starting or active) a
            // change applies at once and shows in the preview above;
            // otherwise the daemon stores it for the next open (the note
            // says which). Last in the tab, so its top is known before its
            // height: past the screen's room its groups scroll, alone.
            Column {
              id: settingsArea
              objectName: "settingsArea"
              width: parent.width
              spacing: Style.space(10)
              visible: root.settingsView.visible || root.recommendedShown

              PanelSeparator { foreground: root.foreground }

              // ---- Use recommended settings (interface revision 20): its
              // title, and on its line the button (as Reset to defaults sits
              // on SETTINGS), then the changes the daemon's row for this
              // camera would make as one line ("2 changes: Sharpness, ...")
              // that opens the list (label: now -> then). Shown only while
              // there are changes, applied only on the button's click.
              Column {
                id: recommendedBlock
                objectName: "recommendedBlock"
                width: parent.width
                spacing: Style.space(6)
                visible: root.recommendedShown

                Item {
                  objectName: "recommendedHeader"
                  width: parent.width
                  height: Math.max(recommendedTitle.implicitHeight, recommendedButton.implicitHeight)

                  PanelSectionHeader {
                    id: recommendedTitle
                    objectName: "recommendedTitle"
                    anchors.left: parent.left
                    anchors.right: recommendedButton.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: Model.RECOMMENDED_TITLE
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Button {
                    id: recommendedButton
                    objectName: "recommendedButton"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.RECOMMENDED_LABEL
                    tooltipText: Model.RECOMMENDED_TOOLTIP
                    bordered: true
                    hasCursor: root.hasCursor("recommended", -1)
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    Accessible.role: Accessible.Button
                    Accessible.name: Model.RECOMMENDED_LABEL
                    Accessible.description: Model.RECOMMENDED_TOOLTIP
                    onHovered: function(on) { if (on) root.setCursor("recommended", -1) }
                    onClicked: root.applyRecommended()
                  }
                }

                // The changes in one line, with the chevron of a settings
                // group's header: a click, Enter or Space opens the list.
                CursorSurface {
                  id: recommendedChangesLine
                  objectName: "recommendedChangesLine"
                  width: parent.width
                  implicitHeight: recommendedSummary.implicitHeight + Style.space(6)
                  hasCursor: root.hasCursor("recommended-changes", -1)
                  foreground: root.foreground
                  fill: root.hoverFill
                  Accessible.role: Accessible.Button
                  Accessible.name: root.health.changes.text
                  Accessible.description: root.health.changes.open ? "Expanded" : "Collapsed"

                  Text {
                    id: recommendedSummary
                    objectName: "recommendedSummary"
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: recommendedGlyph.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: root.health.changes.text
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    id: recommendedGlyph
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    width: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.health.changes.glyph
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.setCursor("recommended-changes", -1)
                    onClicked: root.toggleHealthList("changes")
                  }
                }

                Repeater {
                  objectName: "recommendedChanges"
                  model: root.health.changes.open ? root.health.recommended.length : 0
                  delegate: Text {
                    required property int index
                    objectName: "recommendedChange-" + index
                    textFormat: Text.PlainText
                    width: parent ? parent.width : 0
                    wrapMode: Text.Wrap
                    text: (root.health.recommended[index] || { text: "" }).text
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              SettingsView {
                id: settingsBlock
                objectName: "settingsView"
                // Where this section starts in the panel's column: everything
                // above it is laid out first, so this never depends on the
                // section's own height.
                readonly property real areaTop: tabBlock.y + cameraTab.y + settingsArea.y + y
                width: parent.width
                room: root.contentRoom > 0 ? root.contentRoom - areaTop : 0
                bar: root.bar
                view: root.settingsView
                cursorStop: root.tab === "camera" ? root.currentStop : null
                choiceCursor: root.choiceCursor
                keyCatcher: catcher
                slidersHeld: root.slidersHeld
                foreground: root.foreground
                dim: root.dim
                faint: root.faint
                accent: root.accent
                hoverFill: root.hoverFill
                fontFamily: root.fontFamily
                onCursorRequested: function(kind, index) { root.setCursor(kind, index) }
                onChoiceHovered: function(stop, index) { root.setChoiceCursor(stop, index) }
                onGroupToggled: function(id) { root.toggleGroup(id) }
                onResetRequested: root.resetSettings()
                onHeldChanged: function(delta) { root.slidersHeld = Math.max(0, root.slidersHeld + delta) }
              }
            }
          }

          // ---- Mic: the microphone's own switch and state, then its
          // settings (processing, input device, the default microphone and
          // the audio modules' effects), or why there are none
          Column {
            id: micTab
            objectName: "micTab"
            width: parent.width
            spacing: Style.space(10)
            visible: root.tab === "mic"

            // A daemon (or CLI) that predates the microphone.
            Text {
              objectName: "micHint"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              visible: !root.micView.visible && text !== ""
              text: root.micView.hint
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // The microphone itself, on or off (`mic on|off`).
            Item {
              id: micHostLine
              objectName: "micHostRow"
              width: parent.width
              visible: root.micView.visible
              implicitHeight: Math.max(micHostLabel.implicitHeight, micSwitch.implicitHeight)

              Text {
                id: micHostLabel
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Model.MIC_PRODUCT
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              ToggleSwitch {
                id: micSwitch
                objectName: "micSwitch"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.micView.hostOn
                busy: Daemon.micBusy
                hasCursor: root.hasCursor("mic-host", -1)
                foreground: root.foreground
                accent: root.accent
                onHovered: function(on) { if (on) root.setCursor("mic-host", -1) }
                onToggled: root.toggleMic()
                Accessible.role: Accessible.CheckBox
                Accessible.name: Model.MIC_PRODUCT
                Accessible.checkable: true
                Accessible.checked: root.micView.hostOn

                PanelToolTip {
                  visible: micSwitch.containsMouse
                  text: root.micView.hostOn ? "Turn the microphone off; the previous default microphone comes back if Omarchy Broadcast Mic was the default"
                    : "Turn the microphone on; it starts again at every login"
                  fontFamily: root.fontFamily
                }
              }
            }

            Column {
              objectName: "micStatusBlock"
              width: parent.width
              spacing: Style.space(8)
              visible: root.micView.visible

              Repeater {
                objectName: "micStatusRepeater"
                model: root.micView.rows
                delegate: InfoRow {
                  required property var modelData
                  label: modelData.label
                  value: modelData.value
                }
              }
              // The modules processing it, as the daemon words them.
              Text {
                objectName: "micRunsOn"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.micView.runsOn
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                objectName: "micError"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: root.micView.error
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // ---- the microphone's settings, by the same renderer as the
            // camera's and the effects'; its note says when no audio module
            // is installed. Last in the tab: past the screen's room it
            // scrolls, alone.
            Column {
              id: micSettingsArea
              objectName: "micSettingsArea"
              width: parent.width
              spacing: Style.space(10)
              visible: root.micSettings.visible

              PanelSeparator { foreground: root.foreground }

              SettingsView {
                id: micSettingsBlock
                objectName: "micSettingsView"
                namePrefix: "mic-"
                readonly property real areaTop: tabBlock.y + micTab.y + micSettingsArea.y + y
                width: parent.width
                room: root.contentRoom > 0 ? root.contentRoom - areaTop : 0
                bar: root.bar
                view: root.micSettings
                cursorStop: root.tab === "mic" ? root.currentStop : null
                choiceCursor: root.choiceCursor
                keyCatcher: catcher
                slidersHeld: root.slidersHeld
                foreground: root.foreground
                dim: root.dim
                faint: root.faint
                accent: root.accent
                hoverFill: root.hoverFill
                fontFamily: root.fontFamily
                onCursorRequested: function(kind, index) { root.setCursor(kind, index) }
                onChoiceHovered: function(stop, index) { root.setChoiceCursor(stop, index) }
                onHeldChanged: function(delta) { root.slidersHeld = Math.max(0, root.slidersHeld + delta) }
              }
            }
          }

          // ---- Status: what the daemon reports, then the live figures
          Column {
            id: statusTab
            objectName: "statusTab"
            width: parent.width
            spacing: Style.space(10)
            visible: root.tab === "status"

            Column {
              objectName: "statusBlock"
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                objectName: "statusRepeater"
                model: root.statusRows
                delegate: InfoRow {
                  required property var modelData
                  label: modelData.label
                  value: modelData.value
                }
              }
            }

            // ---- live figures, only while active
            Column {
              objectName: "statsBlock"
              width: parent.width
              spacing: Style.space(8)
              visible: root.statsRows.length > 0

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                text: "LIVE"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Repeater {
                model: root.statsRows
                delegate: InfoRow {
                  required property var modelData
                  label: modelData.label
                  value: modelData.value
                }
              }
            }
          }
        }
      }
    }
  }
}
