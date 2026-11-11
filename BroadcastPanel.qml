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
//           the background image it holds, then the daemon's other global
//           settings (strength, noise removal, ...) drawn generically, or
//           the hint that replaces them (a daemon below revision 9);
//   Camera  the camera list and Next camera, then the camera's settings as
//           the daemon publishes them (SettingsView: groups that open and
//           close, a widget per type, Reset to defaults), or the hint that
//           replaces them;
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
// setting's choices (nothing is written until Enter or Space), move a
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
  // { previewFps } or { panelTab }. Only togglePreview, chooseFps and
  // chooseTab emit it.
  signal settingsRequested(var values)

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
  // The Mic tab: the microphone's own part, then its settings (the groups
  // of surface "mic"), drawn generically.
  readonly property var micView: Model.micView(record)
  readonly property var micSettings: Model.micSettingsView(record, Daemon.settingDrafts)
  // What the keyboard walks and the rows act on: the tab shown's section.
  readonly property var activeView: tab === "effect" ? effectSettings : (tab === "mic" ? micSettings : settingsView)
  readonly property SettingsView activeBlock: tab === "effect" ? effectSettingsBlock : (tab === "mic" ? micSettingsBlock : settingsBlock)
  // A slider is held: the Flickables must not take the drag over.
  property int slidersHeld: 0

  // ---- the tab shown ----------------------------------------------------------
  // Always a word of Model.PANEL_TABS (showTab validates it).
  property string tab: Model.PANEL_TAB_DEFAULT
  readonly property var tabOptions: Model.panelTabOptions(tab)

  // ---- the keyboard cursor (one list of stops; see Model.cursorStops) ------
  // Built from the rendered row count, so the cursor and the rows agree.
  readonly property var stops: Model.cursorStops(record, cameraRepeater.count, previewControls, tab, settingsView, effectSettings, micSettings)
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var currentStop: cursorActive && stops.length > 0
    ? stops[Model.clampCursor(cursorIndex, stops.length)] : null
  // The effect choice under the cursor while the effect row holds it.
  property int effectCursor: 0
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

  function activateCursor() {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "switch") toggleSwitch()
    else if (stop.kind === "mic-host") toggleMic()
    else if (stop.kind === "preview") togglePreview()
    else if (stop.kind === "fps") chooseFps(fpsCursor)
    else if (stop.kind === "tabs") chooseTab(tabCursor)
    else if (stop.kind === "effect") chooseEffect(effectCursor)
    else if (stop.kind === "reset") resetSettings()
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
    else if (stop.kind === "effect") scrollItemIntoView(effectChoices)
    else if (stop.kind === "mic-host") scrollItemIntoView(micHostLine)
    else if (stop.kind === "camera") scrollItemIntoView(cameraRepeater.itemAt(stop.index))
    else scrollItemIntoView(nextButton)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    flick.contentY = 0
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
  Component.onCompleted: {
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
                Accessible.name: modelData.label
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
              visible: root.settingsView.visible

              PanelSeparator { foreground: root.foreground }

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
