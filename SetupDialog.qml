pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The setup dialog: the plugin's overlay entry point (manifest `kinds`
// "overlay", `entryPoints.overlay`), loaded once by the shell (`keepLoaded`)
// as its other overlays are (see the shell's reminders flow). A centred card
// with the sections on the left (Model.SETUP_SECTIONS): Modules (each module,
// its status and an enable switch), Order (the stages in the order they run,
// moved one place at a time where the daemon says the move is valid, and
// Reset order), Backends (the backend profile and each stage's pin), Daemon
// (the daemon's configuration, drawn from its schema by row type) and
// Diagnostics (read-only). One section is shown at a time.
//
// The shell routes the plugin's summon and toggle here, the panel hotkey's
// included, so open() looks at its payload: only the bar widget's right click
// passes {"view":"setup"} (Model.setupPayload); anything else, the hotkey's
// empty payload and the shell's "{}" among them, opens the bar panel instead
// (Daemon.openPanel, on the focused screen). `opened` is true while the
// dialog or any of the widget's panels is shown, so the shell's toggle closes
// either (close() closes both), and the hotkey keeps opening and closing
// the panel.
//
// Data and writes go through the Daemon singleton: holdSetup() starts its
// reads while the dialog is shown (and repeats them on every change the
// watch reports), and every write is an intent of its command queue, one at
// a time, re-read after it ran. Nothing here names a setting, a module or a
// stage: every label, value, reason and choice comes from Model.js views,
// already sanitised, and every Text is PlainText (tests/check-source.py
// counts them).
//
// Keyboard, as in the panel (PanelKeyCatcher, CursorSurface: one cursor, the
// mouse moves it too): 1 to 5 show a section; Tab and Shift+Tab the next and
// previous one; the first arrow key shows the cursor; Up/Down (or k/j) walk
// the section list and then the shown section's controls (Model.setupStops);
// Right from the list goes into the section, Left back to it; on a row of
// choices Left/Right walk them, on a dropdown (an enum of many or long
// choices, as the panel's Model.settingWidget tells them apart) Enter or Space
// opens its list, on a number Left/Right step it, on a stage
// Left/Right pick Move up or Move down; Enter or Space activates; Ctrl+Up/Down
// moves the stage under the cursor; PageUp/PageDown scroll the section,
// and in a section with nothing to act on (Diagnostics, or one that only
// says why it is empty) whose content does not fit, Up/Down scroll it too;
// Escape closes.
//
// The properties the shell's panel loader hands an entry point (omarchyPath,
// shell, manifest, barWidgetRegistry, pluginRegistry, service: shell.qml,
// panelEntry's onLoaded) are only ever writable ones here, or absent: an
// assignment that throws would stop the loader before it registers the
// overlay, which then never opens.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null

  // The dialog is shown (the overlay window is mapped).
  property bool shown: false
  // What the shell reads to tell whether the plugin is open.
  readonly property bool opened: shown || Daemon.panelOpen
  // The section shown: a word of Model.SETUP_SECTIONS (showSection).
  property string section: Model.SETUP_SECTIONS[0]
  // Attached to the Daemon itself (only when no bar widget was: an instance
  // of the singleton of its own).
  property bool attached: false

  readonly property Item keyCatcher: catcher
  // For the test harness: the singleton this overlay reads. (Not `service`:
  // the shell's loader assigns that name.)
  readonly property QtObject daemonService: Daemon
  readonly property var record: Daemon.record
  readonly property var gate: Model.setupGate(record)
  readonly property var sections: Model.setupSectionOptions(section)
  readonly property var modulesView: Model.modulesSectionView(Daemon.setup, record)
  readonly property var orderView: Model.orderSectionView(Daemon.setup, record)
  // The configuration views are only replaced when what they draw changes:
  // `record` is a new object on every line the watch prints (a Stats line
  // about once a second while the camera runs), and a new array makes the
  // repeaters rebuild every row, which would close an open dropdown list.
  readonly property var backendsFresh: Model.backendsSectionView(Daemon.setup, record)
  readonly property var daemonFresh: Model.daemonSectionView(Daemon.setup, record)
  property var backendsView: ({ hint: "", groups: [], stops: 0 })
  property var daemonView: ({ hint: "", groups: [], stops: 0 })
  onBackendsFreshChanged: syncViews()
  onDaemonFreshChanged: syncViews()
  Component.onCompleted: syncViews()
  function syncViews() {
    if (JSON.stringify(backendsFresh) !== JSON.stringify(backendsView)) backendsView = backendsFresh
    if (JSON.stringify(daemonFresh) !== JSON.stringify(daemonView)) daemonView = daemonFresh
  }
  readonly property var diagnostics: Model.diagnosticsView(Daemon.setup, record)
  readonly property var activeView: section === "modules" ? modulesView
    : (section === "order" ? orderView
      : (section === "backends" ? backendsView
        : (section === "daemon" ? daemonView : diagnostics)))
  readonly property var configView: section === "backends" ? backendsView : daemonView
  readonly property string statusText: Daemon.setupBusy ? Model.SETUP_SAVING : Daemon.setupError
  // The last command copied from Diagnostics, for its "Copied" line; how
  // many copies were made (read by the test harness).
  property string copiedText: ""
  property int copies: 0

  // ---- the keyboard cursor (Model.setupStops) ----------------------------------
  readonly property var stops: Model.setupStops(section, activeView)
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var currentStop: cursorActive && stops.length > 0
    ? stops[Model.clampCursor(cursorIndex, stops.length)] : null
  // The choice under the cursor on a config row of choices.
  property int choiceCursor: -1
  // The button under the cursor on a stage row: 0 Move up, 1 Move down.
  property int stageButton: 0

  readonly property color foreground: Commons.Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Commons.Color.accent
  readonly property color hoverFill: Style.hoverFillFor(foreground, accent)
  readonly property string fontFamily: Style.font.family
  readonly property real greyedOpacity: 0.45

  // ---- shell entry points ------------------------------------------------------

  function open(payloadJson) {
    var payload = Model.setupPayload(payloadJson)
    if (payload.view !== "setup") {
      hideDialog()
      var monitor = Hyprland.focusedMonitor
      Daemon.openPanel(monitor ? String(monitor.name || "") : "")
      return
    }
    if (!root.shown) {
      // The bar widgets keep the watch running; a dialog of a singleton no
      // widget has attached to (a reload from another URL) runs its own.
      if (Daemon.attachedCount === 0) {
        Daemon.attach(root)
        Daemon.configure(root, payload.cliSetting)
        root.attached = true
      }
      Daemon.holdSetup(root)
    }
    root.shown = true
    root.cursorActive = false
    root.cursorIndex = Model.SETUP_SECTIONS.indexOf(root.section)
    root.copiedText = ""
    contentFlick.contentY = 0
    Qt.callLater(function() { if (root.shown) catcher.forceActiveFocus() })
  }

  // The shell's hide (and its toggle of an open plugin): the dialog and
  // every panel of the widget close.
  function close() {
    hideDialog()
    Daemon.closePanels()
  }

  function hideDialog() {
    if (!root.shown) return
    root.shown = false
    Daemon.releaseSetup(root)
    if (root.attached) {
      root.attached = false
      Daemon.detach(root)
    }
  }

  // Escape, a click outside the card: closed through the shell, which then
  // forgets the plugin was summoned.
  function dismiss() {
    hideDialog()
    var id = root.manifest && root.manifest.id ? root.manifest.id : ""
    if (id !== "" && root.shell && typeof root.shell.hide === "function") root.shell.hide(id)
  }

  // ---- sections and cursor -------------------------------------------------------

  function showSection(value) {
    var next = Model.setupSectionValue(value)
    root.section = next
    root.choiceCursor = -1
    root.copiedText = ""
    contentFlick.contentY = 0
    if (root.cursorActive) root.cursorIndex = Model.SETUP_SECTIONS.indexOf(next)
  }

  function chooseSection(index) {
    var value = Model.SETUP_SECTIONS[index]
    if (value !== undefined) showSection(value)
  }

  function hasCursor(kind, index) {
    return currentStop !== null && currentStop.kind === kind && currentStop.index === index
  }

  function setCursor(kind, index) {
    for (var i = 0; i < stops.length; i++) {
      if (stops[i].kind === kind && stops[i].index === index) {
        var moved = !cursorActive || Model.clampCursor(cursorIndex, stops.length) !== i
        cursorActive = true
        cursorIndex = i
        if (moved) landOn()
        return
      }
    }
  }

  // Arriving on a row of choices lands on its current choice; on a stage,
  // on the button it offers.
  function landOn() {
    var stop = currentStop
    var row = stop && stop.kind === "config" ? Model.configViewRow(root.configView, stop.index) : null
    root.choiceCursor = row && row.widget === "choices" ? Math.max(0, Model.configSelected(row)) : -1
    if (stop && stop.kind === "stage") root.stageButton = Model.stageButtonAfter(root.orderView.rows[stop.index], root.stageButton, 0)
  }

  function moveCursor(dy) {
    if (stops.length === 0) return
    cursorActive = true
    cursorIndex = Model.clampCursor(Model.clampCursor(cursorIndex, stops.length) + (dy > 0 ? 1 : -1), stops.length)
    landOn()
    scrollCursorIntoView()
  }

  function moveCursorH(dx) {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "section") {
      // Into the section's first control, when it has one.
      if (dx > 0 && stops.length > Model.SETUP_SECTIONS.length) {
        cursorIndex = Model.SETUP_SECTIONS.length
        landOn()
        scrollCursorIntoView()
      }
      return
    }
    if (stop.kind === "stage") {
      var b = Model.stageButtonAfter(root.orderView.rows[stop.index], root.stageButton, dx)
      if (b >= 0 && b !== root.stageButton) { root.stageButton = b; return }
    }
    if (stop.kind === "config") {
      var row = Model.configViewRow(root.configView, stop.index)
      if (row && row.widget === "choices") {
        root.choiceCursor = Math.max(0, Math.min(row.options.length - 1, root.choiceCursor + (dx > 0 ? 1 : -1)))
        return
      }
      if (row && row.widget === "stepper") { stepConfig(row, dx > 0 ? 1 : -1); return }
    }
    // Back to the section list.
    if (dx < 0) setCursor("section", Model.SETUP_SECTIONS.indexOf(root.section))
  }

  function activateCursor() {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "section") chooseSection(stop.index)
    else if (stop.kind === "module") toggleModule(stop.index)
    else if (stop.kind === "stage") moveStage(stop.index, root.stageButton === 1 ? 1 : -1)
    else if (stop.kind === "order-reset") Daemon.resetOrder()
    else if (stop.kind === "config") {
      var row = Model.configViewRow(root.configView, stop.index)
      if (!row) return
      if (row.widget === "switch") Daemon.setConfig(row.id, row.value !== true)
      else if (row.widget === "choices") chooseConfig(row, root.choiceCursor)
      else if (row.widget === "dropdown") openConfigList(stop.index)
    }
  }

  // Enter or Space on a dropdown row: its list opens and takes the keyboard
  // (the shell Dropdown's own keys: Up/Down or j/k walk, Enter chooses,
  // Escape closes); the dialog's key catcher gets it back on close.
  function openConfigList(stop) {
    var item = findConfigItem(stop)
    return item ? item.openList() : false
  }

  // ---- writes (Daemon checks each against the data it read) ---------------------

  function toggleModule(index) {
    var row = root.modulesView.rows[index]
    if (!row || !row.switchable) return false
    return Daemon.setModuleEnabled(row.id, !row.checked)
  }

  function moveStage(index, direction) {
    var moved = Daemon.moveStage(index, direction)
    // The cursor follows the stage it moved.
    if (moved && currentStop && currentStop.kind === "stage") setCursor("stage", index + direction)
    return moved
  }

  function chooseConfig(row, index) {
    var option = row && row.options ? row.options[index] : undefined
    if (!option || option.selected) return false
    return Daemon.setConfig(row.id, option.value)
  }

  // A dropdown's choice, by value (the Dropdown emits the value). The row is
  // a repeater's modelData, whose options are a list, not an Array.
  function chooseConfigValue(row, value) {
    var options = row && row.options ? row.options : []
    for (var i = 0; i < options.length && i < Model.CONFIG_OPTION_CAP; i++)
      if (options[i].value === value) return chooseConfig(row, i)
    return false
  }

  function stepConfig(row, direction) {
    var value = Model.configNudge(Model.findConfigRow(Daemon.setup.config, row.id), direction)
    return value !== null && Daemon.setConfig(row.id, value)
  }

  // ---- scrolling ------------------------------------------------------------------

  // A section with no stops of its own (Diagnostics, a hint) whose content
  // does not fit: Up/Down scroll it.
  function scrollsByKey() {
    return root.stops.length <= Model.SETUP_SECTIONS.length && contentFlick.contentHeight > contentFlick.height + 0.5
  }

  function scrollBy(delta) {
    contentFlick.contentY = Model.scrollTarget(contentFlick.contentY, contentFlick.contentHeight, contentFlick.height, delta)
  }

  function scrollPage(direction) {
    scrollBy(direction * Math.max(Style.space(48), contentFlick.height - Style.space(48)))
  }

  // ---- copying a Diagnostics command ----------------------------------------------

  // The selection a drag made, once it has stopped changing: to the clipboard.
  function copySelection(edit) {
    if (!edit || edit.selectedText === "") return false
    edit.copy()
    root.copiedText = edit.selectedText
    root.copies++
    return true
  }

  function scrollCursorIntoView() {
    var stop = currentStop
    if (!stop || stop.kind === "section") return
    var item = null
    if (stop.kind === "module") item = moduleRepeater.itemAt(stop.index)
    else if (stop.kind === "stage") item = stageRepeater.itemAt(stop.index)
    else if (stop.kind === "order-reset") item = resetOrderButton
    else if (stop.kind === "config") item = findConfigItem(stop.index)
    if (!item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(contentFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height)
      if (top < contentFlick.contentY + margin) contentFlick.contentY = Math.max(0, top - margin)
      else if (bottom > contentFlick.contentY + contentFlick.height - margin)
        contentFlick.contentY = Math.min(maxY, bottom + margin - contentFlick.height)
    })
  }

  function findConfigItem(stop) {
    for (var g = 0; g < configGroupRepeater.count; g++) {
      var group = configGroupRepeater.itemAt(g)
      var found = group ? group.rowItem(stop) : null
      if (found) return found
    }
    return null
  }

  onStopsChanged: if (cursorIndex >= stops.length) cursorIndex = Math.max(0, stops.length - 1)

  // Every read of the setup rebuilds the rows (the repeaters' models are the
  // views' arrays), and a dropdown's list that was open goes with its row,
  // taking the keyboard with it: the key catcher has it back.
  onConfigViewChanged: Qt.callLater(function() { if (root.shown && !catcher.activeFocus) catcher.forceActiveFocus() })

  // ---- pieces -----------------------------------------------------------------------

  // A label and a value on one line, the value right-aligned and elided; a
  // value that is a sentence (`wrap`: the daemon's warning or error, up to 512
  // characters) goes under its label instead, in full and wrapped.
  component InfoRow: Item {
    id: infoRow
    property string label: ""
    property string value: ""
    property bool wrap: false
    width: parent ? parent.width : 0
    implicitHeight: wrap ? infoLabel.implicitHeight + Style.space(2) + infoValue.implicitHeight
      : Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

    // The value keeps at least this much of the line; a long label (a file
    // path) gives way, elided in the middle.
    readonly property real valueRoom: Math.min(infoValue.implicitWidth, Math.max(Style.space(96), width * 0.35))

    Text {
      id: infoLabel
      textFormat: Text.PlainText
      width: infoRow.wrap ? Math.min(implicitWidth, infoRow.width)
        : Math.min(implicitWidth, Math.max(0, infoRow.width - infoRow.valueRoom - Style.space(12)))
      elide: Text.ElideMiddle
      text: infoRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      id: infoValue
      objectName: "infoValue"
      textFormat: Text.PlainText
      x: infoRow.wrap ? 0 : parent.width - width
      y: infoRow.wrap ? infoLabel.implicitHeight + Style.space(2) : 0
      width: infoRow.wrap ? parent.width : Math.max(0, parent.width - infoLabel.width - Style.space(12))
      horizontalAlignment: infoRow.wrap ? Text.AlignLeft : Text.AlignRight
      wrapMode: infoRow.wrap ? Text.Wrap : Text.NoWrap
      elide: infoRow.wrap ? Text.ElideNone : Text.ElideMiddle
      text: infoRow.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // A line of small dim text that takes no room when empty.
  component Note: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 0
    wrapMode: Text.Wrap
    visible: text !== ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  OverlayWindow {
    id: overlay
    shown: root.shown
    WlrLayershell.namespace: "omarchy-broadcast"

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      objectName: "setupCard"
      width: Math.min(Style.space(720), overlay.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), overlay.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      Accessible.role: Accessible.Dialog
      Accessible.name: Model.SETUP_TITLE

      // Clicks inside the card stay inside it.
      MouseArea { anchors.fill: parent; onClicked: {} }

      PanelKeyCatcher {
        id: catcher
        objectName: "setupKeys"
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: card.height - card.contentTopInset - card.contentBottomInset
        reorderable: true
        onMoveRequested: function(dx, dy) {
          if (dy !== 0 && root.scrollsByKey()) { root.scrollBy(dy * Style.space(48)); return }
          // The first key only shows the cursor, as in the shell's panels.
          if (!root.cursorActive) {
            root.cursorActive = true
            root.cursorIndex = Model.SETUP_SECTIONS.indexOf(root.section)
            return
          }
          if (dy !== 0) root.moveCursor(dy)
          else root.moveCursorH(dx)
        }
        onReorderRequested: function(dy) {
          if (root.currentStop && root.currentStop.kind === "stage") root.moveStage(root.currentStop.index, dy > 0 ? 1 : -1)
        }
        onActivateRequested: if (root.cursorActive) root.activateCursor()
        onCloseRequested: root.dismiss()
        onTabRequested: function(direction) {
          var n = Model.SETUP_SECTIONS.length
          root.chooseSection((Model.SETUP_SECTIONS.indexOf(root.section) + direction + n) % n)
        }
        onTextKey: function(t) {
          var n = Model.SETUP_SECTIONS.length
          if (t.length === 1 && t >= "1" && t <= String(n)) root.chooseSection(Number(t) - 1)
        }
        // PanelKeyCatcher passes these through: the section scrolls by a page.
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
            root.scrollPage(event.key === Qt.Key_PageDown ? 1 : -1)
            event.accepted = true
          }
        }

        // ---- title: the dialog's name and, on its line, "Saving…" while a
        // write runs; under it, why the daemon refused the last one (wrapped,
        // at most two lines; it stays until a write goes through)
        Column {
          id: titleLine
          width: parent.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, savingText.implicitHeight)

            Text {
              id: titleText
              objectName: "setupTitle"
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: savingText.left
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: Model.SETUP_TITLE
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              id: savingText
              objectName: "setupSaving"
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Daemon.setupBusy ? Model.SETUP_SAVING : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          Text {
            id: statusLine
            objectName: "setupStatus"
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: Daemon.setupError
            color: Commons.Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- the section list
        Column {
          id: sectionList
          objectName: "setupSections"
          y: titleLine.height + Style.space(14)
          width: Style.space(176)
          spacing: Style.space(2)

          Repeater {
            id: sectionRepeater
            model: root.sections
            delegate: CursorSurface {
              id: sectionItem
              required property var modelData
              required property int index
              objectName: "setupSection-" + modelData.value
              width: sectionList.width
              implicitHeight: sectionLabel.implicitHeight + Style.spacing.controlPaddingY * 2
              hasCursor: root.hasCursor("section", index)
              current: modelData.selected
              foreground: root.foreground
              accent: root.accent
              Accessible.role: Accessible.PageTab
              Accessible.name: modelData.label
              Accessible.description: modelData.description
              Accessible.selectable: true
              Accessible.selected: modelData.selected

              Text {
                id: sectionNumber
                textFormat: Text.PlainText
                x: Style.spacing.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: sectionItem.modelData.number
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                id: sectionLabel
                textFormat: Text.PlainText
                anchors.left: sectionNumber.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: sectionItem.modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setCursor("section", sectionItem.index)
                onClicked: root.chooseSection(sectionItem.index)
              }
            }
          }
        }

        Rectangle {
          x: sectionList.width + Style.space(12)
          y: sectionList.y
          width: 1
          height: parent.height - sectionList.y
          color: Qt.darker(root.foreground, 3.2)
        }

        // ---- the section shown
        Flickable {
          id: contentFlick
          objectName: "setupFlick"
          x: sectionList.width + Style.space(26)
          y: sectionList.y
          width: parent.width - x
          height: parent.height - y
          contentWidth: width
          contentHeight: content.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height + 0.5
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: content
            x: Style.space(2)
            width: contentFlick.width - Style.space(14)
            spacing: Style.space(12)

            PanelSectionHeader {
              text: (root.sections[Model.SETUP_SECTIONS.indexOf(root.section)] || { label: "" }).label
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Why the section shows nothing (loading, an old daemon, a read
            // that failed, nothing installed); the unavailable daemon's hint
            // and command with it.
            Column {
              objectName: "setupHintBlock"
              width: parent.width
              spacing: Style.space(6)
              visible: root.section !== "diagnostics" && root.activeView.hint !== ""

              Text {
                objectName: "setupHint"
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: root.activeView.hint || ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Note { text: root.gate.text !== "" && root.activeView.hint === root.gate.text ? root.gate.hint : "" }
              // Shown, never run.
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: root.gate.text !== "" && root.activeView.hint === root.gate.text ? root.gate.commandText : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            // ---- Modules
            Column {
              objectName: "modulesSection"
              width: parent.width
              spacing: Style.space(6)
              visible: root.section === "modules" && root.modulesView.hint === ""

              Repeater {
                id: moduleRepeater
                model: root.modulesView.rows
                delegate: CursorSurface {
                  id: moduleRow
                  required property var modelData
                  required property int index
                  objectName: "moduleRow-" + index
                  width: parent ? parent.width : 0
                  implicitHeight: moduleText.implicitHeight + Style.spacing.controlPaddingY * 2
                  hasCursor: root.hasCursor("module", index)
                  foreground: root.foreground
                  accent: root.accent
                  Accessible.role: Accessible.CheckBox
                  Accessible.name: modelData.title
                  Accessible.description: modelData.statusLine
                    + (modelData.forcedText !== "" ? ", " + modelData.forcedText : "")
                    + (modelData.stageNotes !== "" ? ". " + modelData.stageNotes.split("\n").join("; ") : "")
                    + (modelData.note !== "" ? ". " + modelData.note : "")
                  Accessible.checkable: true
                  Accessible.checked: modelData.checked

                  Column {
                    id: moduleText
                    x: Style.spacing.controlPaddingX
                    y: Style.spacing.controlPaddingY
                    width: parent.width - x * 2 - moduleSwitch.width - Style.space(12)
                    spacing: Style.space(2)

                    Text {
                      id: moduleTitle
                      objectName: "moduleTitle-" + moduleRow.index
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: moduleRow.modelData.title
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body

                      // The whole name, when it is elided.
                      PanelToolTip {
                        objectName: "moduleTitleTip-" + moduleRow.index
                        visible: moduleTitle.truncated && moduleMouse.containsMouse
                        text: moduleRow.modelData.title
                      }
                    }
                    Note { text: moduleRow.modelData.statusLine }
                    // The debug override is marked by its own urgent line; the "Forced:" lead keeps colour from being the only cue.
                    Note { text: moduleRow.modelData.forcedText; color: Commons.Color.urgent }
                    Note { text: moduleRow.modelData.stagesText; font.pixelSize: Style.font.caption }
                    Note { text: moduleRow.modelData.stageNotes; font.pixelSize: Style.font.caption }
                    Note { text: moduleRow.modelData.note }
                  }
                  ToggleSwitch {
                    id: moduleSwitch
                    objectName: "moduleSwitch-" + moduleRow.index
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: moduleRow.modelData.switchable ? 1.0 : root.greyedOpacity
                    checked: moduleRow.modelData.checked
                    busy: Daemon.setupBusy
                    interactive: false
                    cursorRing: false
                    foreground: root.foreground
                    accent: root.accent
                  }
                  // The row owns its click, as the shell's Toggle row does.
                  MouseArea {
                    id: moduleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: moduleRow.modelData.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: root.setCursor("module", moduleRow.index)
                    onClicked: root.toggleModule(moduleRow.index)
                  }
                }
              }
              Note { text: root.modulesView.truncation }
            }

            // ---- Order
            Column {
              objectName: "orderSection"
              width: parent.width
              spacing: Style.space(6)
              visible: root.section === "order" && root.orderView.hint === ""

              Note { text: root.orderView.note }

              Repeater {
                id: stageRepeater
                model: root.orderView.rows
                delegate: CursorSurface {
                  id: stageRow
                  required property var modelData
                  required property int index
                  objectName: "stageRow-" + index
                  width: parent ? parent.width : 0
                  implicitHeight: Math.max(stageText.implicitHeight, stageButtons.implicitHeight) + Style.spacing.controlPaddingY * 2
                  // The cursor is drawn on the button it is on, not the row.
                  hasCursor: false
                  foreground: root.foreground
                  accent: root.accent
                  Accessible.role: Accessible.ListItem
                  Accessible.name: modelData.position + ". " + modelData.id
                  Accessible.description: modelData.slot

                  Column {
                    id: stageText
                    x: Style.spacing.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x * 2 - stageButtons.width - Style.space(12)
                    spacing: Style.space(2)
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: stageRow.modelData.position + ".  " + stageRow.modelData.id
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Note { text: stageRow.modelData.slot; font.pixelSize: Style.font.caption }
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.setCursor("stage", stageRow.index)
                  }
                  Row {
                    id: stageButtons
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.md

                    Button {
                      objectName: "stageUp-" + stageRow.index
                      text: "Move up"
                      bordered: true
                      opacity: stageRow.modelData.up ? 1.0 : root.greyedOpacity
                      enabled: stageRow.modelData.up
                      hasCursor: root.hasCursor("stage", stageRow.index) && root.stageButton === 0
                      foreground: root.foreground
                      background: Commons.Color.background
                      accent: root.accent
                      fontFamily: root.fontFamily
                      Accessible.name: "Move " + stageRow.modelData.id + " up"
                      onHovered: function(on) { if (on) { root.setCursor("stage", stageRow.index); root.stageButton = 0 } }
                      onClicked: root.moveStage(stageRow.index, -1)
                    }
                    Button {
                      objectName: "stageDown-" + stageRow.index
                      text: "Move down"
                      bordered: true
                      opacity: stageRow.modelData.down ? 1.0 : root.greyedOpacity
                      enabled: stageRow.modelData.down
                      hasCursor: root.hasCursor("stage", stageRow.index) && root.stageButton === 1
                      foreground: root.foreground
                      background: Commons.Color.background
                      accent: root.accent
                      fontFamily: root.fontFamily
                      Accessible.name: "Move " + stageRow.modelData.id + " down"
                      onHovered: function(on) { if (on) { root.setCursor("stage", stageRow.index); root.stageButton = 1 } }
                      onClicked: root.moveStage(stageRow.index, 1)
                    }
                  }
                }
              }

              Button {
                id: resetOrderButton
                objectName: "resetOrder"
                visible: root.orderView.reset
                text: Model.ORDER_RESET_LABEL
                bordered: true
                hasCursor: root.hasCursor("order-reset", -1)
                foreground: root.foreground
                background: Commons.Color.background
                accent: root.accent
                fontFamily: root.fontFamily
                onHovered: function(on) { if (on) root.setCursor("order-reset", -1) }
                onClicked: Daemon.resetOrder()
              }
            }

            // ---- Backends and Daemon: config rows by type
            Column {
              objectName: "configSection"
              width: parent.width
              spacing: Style.space(14)
              visible: (root.section === "backends" || root.section === "daemon") && root.configView.hint === ""

              Repeater {
                id: configGroupRepeater
                model: root.configView.groups
                delegate: Column {
                  id: configGroup
                  required property var modelData
                  required property int index
                  width: parent ? parent.width : 0
                  spacing: Style.space(6)

                  function rowItem(stop) {
                    for (var i = 0; i < configRowRepeater.count; i++) {
                      var it = configRowRepeater.itemAt(i)
                      if (it && it.row.stop === stop) return it
                    }
                    return null
                  }

                  // As the panel's section headers (SettingsView), uppercased.
                  PanelSectionHeader {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: root.configView.groups.length > 1
                    text: configGroup.modelData.label.toUpperCase()
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Repeater {
                    id: configRowRepeater
                    model: configGroup.modelData.rows
                    delegate: CursorSurface {
                      id: configRow
                      required property var modelData
                      readonly property var row: modelData
                      objectName: "configRow-" + modelData.id
                      width: parent ? parent.width : 0

                      // A dropdown is wide enough for its longest label (the
                      // list's rows are as wide as the box), within the line.
                      readonly property real listWidth: row.widget === "dropdown"
                        ? widestOption() + 2 * Style.spacing.controlPaddingX + Style.space(36) : 0
                      TextMetrics {
                        id: optionProbe
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                      function widestOption() {
                        var widest = 0
                        for (var i = 0; i < row.options.length; i++) {
                          optionProbe.text = row.options[i].label
                          widest = Math.max(widest, optionProbe.advanceWidth)
                        }
                        return widest
                      }

                      // Opens a dropdown row's list; false on any other row.
                      function openList() {
                        if (row.widget !== "dropdown") return false
                        configList.open()
                        return true
                      }

                      implicitHeight: configColumn.implicitHeight + Style.spacing.controlPaddingY * 2
                      // One highlight: the row's on a switch or a number, the
                      // chip's on a row of choices, the box's on a dropdown.
                      hasCursor: row.stop >= 0 && root.hasCursor("config", row.stop)
                        && row.widget !== "choices" && row.widget !== "dropdown"
                      foreground: root.foreground
                      accent: root.accent
                      // As SettingsView maps its rows: a switch is a check
                      // box, a number a spin box, a row of choices a combo
                      // box (as is a dropdown); a value only shown is text.
                      Accessible.role: row.widget === "switch" ? Accessible.CheckBox
                        : (row.widget === "stepper" ? Accessible.SpinBox
                          : (row.widget === "choices" || row.widget === "dropdown" ? Accessible.ComboBox : Accessible.StaticText))
                      Accessible.name: row.label
                      Accessible.description: row.valueText + (row.note !== "" ? ". " + row.note : "")
                        + (row.description !== "" ? ". " + row.description : "")
                      Accessible.checkable: row.widget === "switch"
                      Accessible.checked: row.widget === "switch" && row.value === true

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: configRow.row.widget === "switch" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: if (configRow.row.stop >= 0) root.setCursor("config", configRow.row.stop)
                        onClicked: if (configRow.row.widget === "switch") Daemon.setConfig(configRow.row.id, configRow.row.value !== true)
                      }

                      Column {
                        id: configColumn
                        x: Style.spacing.controlPaddingX
                        y: Style.spacing.controlPaddingY
                        width: parent.width - x * 2
                        spacing: Style.space(3)

                        // The label, and on its line the switch, the number
                        // or the value; a row of choices goes on its own
                        // line under the label.
                        Item {
                          width: parent.width
                          implicitHeight: Math.max(configLabel.implicitHeight, configWidget.implicitHeight)

                          Text {
                            id: configLabel
                            textFormat: Text.PlainText
                            anchors.left: parent.left
                            anchors.right: configWidget.left
                            anchors.rightMargin: configWidget.width > 0 ? Style.space(10) : 0
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: configRow.row.label
                            color: configRow.row.greyed ? root.dim : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                          }

                          Item {
                            id: configWidget
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: configRow.row.widget === "switch" ? configSwitch.implicitWidth
                              : (configRow.row.widget === "choices" ? 0
                                : (configRow.row.widget === "dropdown" ? Math.min(Math.max(Style.space(260), configRow.listWidth), configColumn.width * 0.7)
                                  : (configRow.row.widget === "stepper" ? configStepper.implicitWidth
                                    : Math.min(configValue.implicitWidth, configColumn.width * 0.55))))
                            implicitHeight: configRow.row.widget === "switch" ? configSwitch.implicitHeight
                              : (configRow.row.widget === "choices" ? 0
                                : (configRow.row.widget === "dropdown" ? configList.implicitHeight
                                  : (configRow.row.widget === "stepper" ? configStepper.implicitHeight : configValue.implicitHeight)))
                            width: implicitWidth
                            height: implicitHeight

                            ToggleSwitch {
                              id: configSwitch
                              objectName: "configSwitch-" + configRow.row.id
                              anchors.right: parent.right
                              visible: configRow.row.widget === "switch"
                              checked: configRow.row.value === true
                              busy: Daemon.setupBusy
                              interactive: false
                              cursorRing: false
                              foreground: root.foreground
                              accent: root.accent
                            }

                            Row {
                              id: configStepper
                              anchors.right: parent.right
                              visible: configRow.row.widget === "stepper"
                              spacing: Style.space(6)

                              Button {
                                objectName: "configLess-" + configRow.row.id
                                text: "−"
                                bordered: true
                                foreground: root.foreground
                                background: Commons.Color.background
                                accent: root.accent
                                fontFamily: root.fontFamily
                                Accessible.name: "Less " + configRow.row.label
                                onHovered: function(on) { if (on) root.setCursor("config", configRow.row.stop) }
                                onClicked: root.stepConfig(configRow.row, -1)
                              }
                              Text {
                                objectName: "configStepValue-" + configRow.row.id
                                textFormat: Text.PlainText
                                anchors.verticalCenter: parent.verticalCenter
                                width: Style.space(88)
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideLeft
                                text: configRow.row.valueText
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                              }
                              Button {
                                objectName: "configMore-" + configRow.row.id
                                text: "+"
                                bordered: true
                                foreground: root.foreground
                                background: Commons.Color.background
                                accent: root.accent
                                fontFamily: root.fontFamily
                                Accessible.name: "More " + configRow.row.label
                                onHovered: function(on) { if (on) root.setCursor("config", configRow.row.stop) }
                                onClicked: root.stepConfig(configRow.row, 1)
                              }
                            }

                            // An enum of many or long choices (Model.configWidget):
                            // the shell's Dropdown, its list over the rows
                            // below. The Dropdown sets its own value on a
                            // choice: bound to the row's again, so the
                            // daemon's word shows (a refused write reverts).
                            Dropdown {
                              id: configList
                              objectName: "configDropdown-" + configRow.row.id
                              anchors.left: parent.left
                              anchors.right: parent.right
                              anchors.verticalCenter: parent.verticalCenter
                              visible: configRow.row.widget === "dropdown"
                              showLabel: false
                              options: configRow.row.widget === "dropdown" ? configRow.row.options : []
                              value: typeof configRow.row.value === "string" ? configRow.row.value : ""
                              hasCursor: root.hasCursor("config", configRow.row.stop)
                              foreground: root.foreground
                              accent: root.accent
                              fontFamily: root.fontFamily
                              Accessible.name: configRow.row.label
                              onHovered: function(isHovered) { if (isHovered) root.setCursor("config", configRow.row.stop) }
                              onChanged: function(value) {
                                configList.value = Qt.binding(function() { return typeof configRow.row.value === "string" ? configRow.row.value : "" })
                                root.chooseConfigValue(configRow.row, value)
                              }
                              onPopupOpenChanged: if (!popupOpen && root.shown) catcher.forceActiveFocus()
                            }

                            Text {
                              id: configValue
                              objectName: "configValue-" + configRow.row.id
                              textFormat: Text.PlainText
                              anchors.right: parent.right
                              width: Math.min(implicitWidth, configColumn.width * 0.55)
                              visible: configRow.row.widget === "text"
                              horizontalAlignment: Text.AlignRight
                              elide: Text.ElideMiddle
                              text: configRow.row.valueText
                              color: configRow.row.greyed ? root.dim : root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                            }
                          }
                        }

                        // A row of choices, in the daemon's order, from the
                        // left across the whole row, wrapping onto a next
                        // line when they do not fit; a chip wider than the
                        // row elides its label (its tooltip has it whole).
                        Flow {
                          id: configChoices
                          objectName: "configChoices-" + configRow.row.id
                          width: parent.width
                          visible: configRow.row.widget === "choices"
                          spacing: Style.space(6)

                          Repeater {
                            model: configRow.row.widget === "choices" ? configRow.row.options.length : 0
                            delegate: Button {
                              id: choiceChip
                              required property int index
                              readonly property var option: configRow.row.options[index]
                              objectName: "configChoice-" + configRow.row.id + "-" + index
                              width: Math.min(implicitWidth, configChoices.width)
                              text: option ? option.label : ""
                              tooltipText: implicitWidth > configChoices.width && option ? option.label : ""
                              selected: !!option && option.selected
                              bordered: true
                              hasCursor: root.hasCursor("config", configRow.row.stop) && root.choiceCursor === index
                              foreground: root.foreground
                              background: Commons.Color.background
                              accent: root.accent
                              fontFamily: root.fontFamily
                              Accessible.role: Accessible.RadioButton
                              Accessible.name: option ? option.label : ""
                              Accessible.checkable: true
                              Accessible.checked: !!option && option.selected
                              onHovered: function(on) {
                                if (!on) return
                                root.setCursor("config", configRow.row.stop)
                                root.choiceCursor = choiceChip.index
                              }
                              onClicked: root.chooseConfig(configRow.row, choiceChip.index)
                            }
                          }
                        }

                        Note { text: configRow.row.description; font.pixelSize: Style.font.caption }
                        Note { objectName: "configNote-" + configRow.row.id; text: configRow.row.note }
                        Note { text: configRow.row.applyText; font.pixelSize: Style.font.caption }
                      }
                    }
                  }
                }
              }
            }

            // ---- Diagnostics (read-only)
            Column {
              objectName: "diagnosticsSection"
              width: parent.width
              spacing: Style.space(8)
              visible: root.section === "diagnostics"

              Repeater {
                model: root.diagnostics.rows
                delegate: InfoRow {
                  required property var modelData
                  objectName: "diagnosticRow-" + modelData.label
                  label: modelData.label
                  value: modelData.value
                  wrap: modelData.value.length > Model.INFO_WRAP_CHARS
                }
              }

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                width: parent.width
                wrapMode: Text.Wrap
                text: "CONFIGURATION FILES, IN LOAD ORDER"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Note { text: root.diagnostics.filesHint }
              Note { text: root.diagnostics.dir; elide: Text.ElideLeft; wrapMode: Text.NoWrap }
              Repeater {
                model: root.diagnostics.files
                delegate: Column {
                  id: fileRow
                  required property var modelData
                  width: parent ? parent.width : 0
                  spacing: Style.space(2)
                  InfoRow { label: fileRow.modelData.path; value: fileRow.modelData.statusText }
                  Note { text: fileRow.modelData.reason }
                  Note { text: fileRow.modelData.note; font.pixelSize: Style.font.caption }
                }
              }

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                width: parent.width
                wrapMode: Text.Wrap
                text: "MODULE PROBLEMS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Note { text: root.diagnostics.problemsHint }
              Repeater {
                model: root.diagnostics.problems
                delegate: Column {
                  id: problemRow
                  required property var modelData
                  width: parent ? parent.width : 0
                  spacing: Style.space(2)
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    text: problemRow.modelData.title
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Note { text: problemRow.modelData.reason }
                }
              }

              PanelSeparator { foreground: root.foreground }
              PanelSectionHeader {
                width: parent.width
                wrapMode: Text.Wrap
                text: "COMMANDS TO RUN IN A TERMINAL (SELECT TO COPY)"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              // Shown, never run; selected with the mouse, a command (or the
              // part selected) is copied once the selection stops changing.
              // The keyboard stays with the dialog (activeFocusOnPress off);
              // the selection stays drawn without focus.
              Repeater {
                model: root.diagnostics.commands
                delegate: TextEdit {
                  id: commandEdit
                  required property var modelData
                  objectName: "diagnosticCommand"
                  textFormat: TextEdit.PlainText
                  width: parent ? parent.width : 0
                  readOnly: true
                  selectByMouse: true
                  activeFocusOnPress: false
                  persistentSelection: true
                  wrapMode: TextEdit.WrapAnywhere
                  text: modelData
                  color: root.foreground
                  selectionColor: root.accent
                  selectedTextColor: Commons.Color.menu.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  onSelectedTextChanged: if (selectedText !== "") copyTimer.restart()

                  Timer {
                    id: copyTimer
                    interval: 300
                    repeat: false
                    onTriggered: root.copySelection(commandEdit)
                  }
                }
              }
              Note {
                objectName: "diagnosticCopied"
                text: root.copiedText !== "" ? "Copied: " + root.copiedText : ""
              }
            }
          }
        }
      }
    }
  }
}
