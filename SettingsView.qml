pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The camera's settings, drawn generically from Model.settingsView:
// whatever the daemon publishes, in its groups and order, through one widget
// per type:
//   int     the shell's PanelSlider, with the value and its unit; an int of
//           exactly two values is a switch (Model.settingWidget)
//   bool    the shell's ToggleSwitch (as the shell's panels draw a row switch;
//           the row owns its click)
//   enum    a row of the shell's Buttons (its ButtonGroup) up to
//           Model.SEGMENTED_MAX_OPTIONS short choices, else its Dropdown
//   action  a Button
// A group is a header that opens and closes, one open at a time (memory only:
// the panel holds the choice, Model.openGroupId), or, where the view says it
// is not collapsible (the Effect and Mic tabs'), a plain heading over rows
// that are always shown, or no heading at all where the group is one master
// and its dependents (the view's `heading`). The view lists only the rows
// drawn in place (Model.settingPlacement): a dependent shows indented under
// its master (`depth`) once the daemon allows it; a row the daemon greys in
// place keeps its label and value legible, only its control is faded, and it
// takes no input. What a row says beyond its label (its reason while greyed,
// its description: the view's `help`) shows only under the cursor, which the
// pointer moves too, as a tip drawn over the panel (never in the layout),
// marked by a faint "?" after the label. What cannot run
// here is one counted line at the foot ("Not available now (n)", the
// panel's notAvailable, Model.notAvailableView), opened to its entries and
// their reasons, with a Setup button where something is not installed.
// Nothing here knows any setting: no id is named, every label, unit, reason
// and choice comes from the view, already sanitised by Model.js (markup
// characters removed), and every Text is PlainText (tests/check-source.py
// counts them).
//
// Layout: the note, the groups, the "Not available now" line, then Reset to
// defaults as a quiet link at the bottom (the Camera tab's). No scroller of
// its own: the panel's body is the one scroller.
//
// The repeaters' models are counts, not the view's arrays: a delta changes
// what a row shows, never rebuilds it, so the slider under the mouse stays the
// same item through a drag. That item can come to show another setting (a new
// set, another camera): a slider held then lets go and writes nothing, and an
// open dropdown closes (`rowKey`, the view's setKey and the row's id). Writes
// go to the Daemon singleton (a draft first, see Daemon.moveSetting); the
// keyboard cursor is the panel's (`cursorStop`, a stop of Model.cursorStops,
// and `choiceCursor`, the chip under it on a row of buttons), and hovering
// asks the panel to move it. One highlight at a time: the row draws it on a
// slider or a switch row (and on any greyed row), the chip under the chip
// cursor on a row of buttons, the box on a dropdown, the button on an action.
Column {
  id: root

  property QtObject bar: null
  // Put before the objectName of the section's own parts (settingsNote,
  // settingsReset, ...), so that two sections in one panel are told apart.
  property string namePrefix: ""
  // Model.settingsView(record, open, drafts), or Model.effectSettingsView /
  // micSettingsView (no Reset, groups that stay open).
  property var view: ({ visible: false, hint: "", note: "", groups: [], truncation: "", reset: false, rowCount: 0, setKey: "",
                        title: "", collapsible: true, unavailable: [] })
  // The view's "Not available now" line, as the panel holds it open or
  // closed (Model.notAvailableView).
  property var notAvailable: ({ visible: false, count: 0, text: "", open: false, glyph: "", entries: [], note: "" })
  // The panel's current stop ({ kind, index }) or null, and its chip cursor.
  property var cursorStop: null
  property int choiceCursor: -1
  // Where the keyboard goes back to once a dropdown's list closes.
  property Item keyCatcher: null
  // The visible area the section scrolls in (the panel's body): a help tip
  // that would run past its bottom is drawn above its row instead.
  property Item viewport: null
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color faint: Qt.darker(foreground, 1.8)
  property color accent: Commons.Color.accent
  property color hoverFill: Style.hoverFillFor(foreground, accent)
  property string fontFamily: Style.font.family
  // A greyed row's control (never its text).
  readonly property real greyedOpacity: 0.45

  // The mouse is over a stop: the panel moves its one cursor there.
  signal cursorRequested(string kind, int index)
  // The mouse is over chip `index` of the row at keyboard stop `stop`.
  signal choiceHovered(int stop, int index)
  // A group header was clicked: the panel opens or closes the group.
  signal groupToggled(string id)
  // Reset to defaults was clicked.
  signal resetRequested()
  // The "Not available now" line was clicked: it opens or folds.
  signal notAvailableToggled()
  // An entry's Setup button was clicked: the setup dialog.
  signal setupRequested(int index)
  // A slider was grabbed (+1) or let go (-1): the panel's body must not take
  // the drag over.
  signal heldChanged(int delta)

  // The left inset of headings and rows: none in the Effect and Mic tabs,
  // where they line up with the panel's own rows. On the right every
  // control ends on the one edge the panel's own controls end on (the
  // section's width), whatever the tab.
  readonly property real inset: view.collapsible === false ? 0 : Style.space(6)
  // How far a dependent is drawn in, under its master.
  readonly property real depthInset: Style.space(18)
  readonly property Item resetItem: resetButton
  readonly property Item notAvailableItem: notAvailableLine

  spacing: Style.space(8)
  visible: view.visible
  // Above what the panel draws after the section, for the help tips.
  z: 1

  function hasCursor(kind, index) {
    return cursorStop !== null && cursorStop !== undefined && cursorStop.kind === kind
      && (!Model.stopHasIndex(kind) || cursorStop.index === index)
  }

  // The header of the group at `index` of the view, or null.
  function groupItem(index) {
    var block = groupRepeater.itemAt(index)
    return block ? block.header : null
  }

  // The row drawn for keyboard stop `stop`, or null.
  function rowItem(stop) {
    for (var g = 0; g < groupRepeater.count; g++) {
      var block = groupRepeater.itemAt(g)
      var found = block ? block.rowFor(stop) : null
      if (found) return found
    }
    return null
  }

  // The Setup button of entry `index` of the "Not available now" list, or null.
  function setupItem(index) {
    var entry = unavailableRepeater.itemAt(index)
    return entry ? entry.button : null
  }

  // Enter or Space on a dropdown row: its list opens and takes the keyboard
  // (the shell Dropdown's own keys: Up/Down or j/k walk, Enter chooses,
  // Escape closes); the panel's key catcher gets it back on close.
  function openChoices(stop) {
    var item = rowItem(stop)
    return item ? item.openChoices() : false
  }

  // Where a change applies: live, or at the camera's next open.
  Text {
    id: noteText
    objectName: root.namePrefix + "settingsNote"
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.Wrap
    visible: text !== ""
    text: root.view.note
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // Instead of the settings: an old CLI or daemon, a newer settings schema,
  // or a camera with nothing to show.
  Text {
    id: hintText
    objectName: root.namePrefix + "settingsHint"
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.Wrap
    visible: text !== ""
    text: root.view.hint
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Column {
    id: groupsColumn
    objectName: root.namePrefix + "settingsGroups"
    width: parent.width
    visible: root.view.groups.length > 0
    // Over the siblings drawn after it (the Not available block, the
    // truncation note, Reset): the last row's help tip, opening downward,
    // stays on top of them.
    z: 1
    // Headers and rows carry their own padding: between groups the same
    // step as between the rows of one (groupBlock's spacing), so rows keep
    // one rhythm whichever group they are in.
    spacing: Style.space(1)

    Repeater {
      id: groupRepeater
      objectName: root.namePrefix + "settingsGroupRepeater"
      model: root.view.groups.length

      delegate: Column {
        id: groupBlock
        required property int index
        readonly property var group: root.view.groups[index] || ({ id: "", label: "", heading: false, expanded: false, glyph: "", rows: [], truncation: "", breakAbove: "" })
        readonly property Item header: groupHeader
        objectName: root.namePrefix + "settingsGroup-" + group.id
        width: groupsColumn.width
        spacing: Style.space(1)
        // Above the groups after it while one of its rows has the cursor,
        // so the row's help tip draws over them.
        z: root.cursorStop && root.cursorStop.kind === "setting"
          && group.rows.some(function(r) { return r.stop === root.cursorStop.index }) ? 1 : 0

        // Not collapsible (the Effect and Mic tabs): the group's break
        // (Model.markGroupBreaks): a gap above a heading, a gap with a faint
        // line where rows with no heading follow a headed section (so they
        // never read as its items), else nothing: every row keeps one rhythm.
        Item {
          objectName: root.namePrefix + "settingsGroupBreak-" + groupBlock.group.id
          readonly property string kind: root.view.collapsible === false ? (groupBlock.group.breakAbove || "") : ""
          width: parent.width
          height: Style.space(8)
          visible: kind !== ""

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            visible: parent.kind === "rule"
            color: root.faint
            opacity: 0.5
          }
        }

        function rowFor(stop) {
          for (var r = 0; r < rowRepeater.count; r++) {
            var item = rowRepeater.itemAt(r)
            if (item && item.row.stop === stop) return item
          }
          return null
        }

        // The header: the group's label, aligned with its rows' labels,
        // and the chevron at the right edge; Enter, Space or a click
        // opens or closes it.
        CursorSurface {
          id: groupHeader
          objectName: root.namePrefix + "settingsGroupHeader-" + groupBlock.group.id
          // Not collapsible: only where the view heads the group (a group
          // that is one master and its dependents has none).
          visible: root.view.collapsible !== false || groupBlock.group.heading === true
          width: parent.width
          implicitHeight: headerLabel.implicitHeight + Style.space(6)
          hasCursor: root.hasCursor("group", groupBlock.index)
          foreground: root.foreground
          fill: root.hoverFill
          Accessible.role: root.view.collapsible !== false ? Accessible.Button : Accessible.StaticText
          Accessible.name: groupBlock.group.label
          Accessible.description: root.view.collapsible === false ? "" : (groupBlock.group.expanded ? "Expanded" : "Collapsed")

          Text {
            id: headerLabel
            objectName: root.namePrefix + "settingsGroupLabel-" + groupBlock.group.id
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: root.inset
            anchors.right: headerGlyph.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            // Collapsible: bold body text. Not (the Effect tab): the look of
            // the panel's section headers (PanelSectionHeader), small caps.
            readonly property bool section: root.view.collapsible === false
            text: section ? groupBlock.group.label.toUpperCase() : groupBlock.group.label
            color: section ? Qt.darker(root.foreground, 1.4) : root.foreground
            font.family: root.fontFamily
            font.pixelSize: section ? Style.font.caption : Style.font.body
            font.bold: true
          }
          Text {
            id: headerGlyph
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            width: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: groupBlock.group.glyph
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.view.collapsible !== false
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.cursorRequested("group", groupBlock.index)
            onClicked: root.groupToggled(groupBlock.group.id)
          }
        }

        Repeater {
          id: rowRepeater
          model: groupBlock.group.rows.length

          delegate: CursorSurface {
            id: settingRow
            required property int index
            readonly property var row: groupBlock.group.rows[index] || ({ id: "", type: "", widget: "", label: "", enabled: false, greyed: true,
                                                                          kind: "", reason: "", description: "", help: "", depth: 0, checked: false,
                                                                          displayOffset: null, displayScale: null, value: null, valueText: "", min: 0, max: 1,
                                                                          step: 1, options: [], selectedIndex: -1, optionsNote: "", stop: -1 })
            readonly property bool greyed: !row.enabled
            readonly property bool onCursor: root.hasCursor("setting", row.stop)
            // The row draws the cursor (see the header comment).
            readonly property bool rowDrawsCursor: greyed || row.widget === "slider" || row.widget === "switch"
            // Which set and which setting this item shows now.
            readonly property string rowKey: root.view.setKey + "\n" + row.id
            objectName: "setting-" + row.id
            width: groupBlock.width
            implicitHeight: rowColumn.implicitHeight + Style.space(4)
            // Above the rows after it, so its help tip draws over them.
            z: onCursor ? 1 : 0
            hasCursor: onCursor && rowDrawsCursor
            outline: true
            foreground: root.foreground
            fill: root.hoverFill
            Accessible.role: row.widget === "slider" ? Accessible.Slider
              : (row.widget === "switch" ? Accessible.CheckBox
                : (row.widget === "action" ? Accessible.Button : Accessible.ComboBox))
            // The whole label, however it is elided on screen.
            Accessible.name: row.label
            Accessible.description: Model.settingDescription(row)
            Accessible.checkable: row.widget === "switch"
            Accessible.checked: row.widget === "switch" && row.value === true

            function openChoices() {
              if (settingRow.greyed || settingRow.row.widget !== "dropdown" || !widget.item) return false
              widget.item.openList()
              return true
            }

            // Where the row as a whole is the target (a slider's row, a
            // greyed row, a row with help to show): hovering it moves the
            // cursor there. A switch row's MouseArea below does the same;
            // elsewhere the widget is the target and reports its own hover.
            HoverHandler {
              enabled: settingRow.row.widget === "slider" || settingRow.greyed || settingRow.row.help !== ""
              onHoveredChanged: if (hovered) root.cursorRequested("setting", settingRow.row.stop)
            }

            Column {
              id: rowColumn
              // A dependent is drawn in, under its master.
              x: root.inset + (settingRow.row.depth === 1 ? root.depthInset : 0)
              y: Style.space(2)
              width: parent.width - x
              spacing: Style.space(1)

              // The label on the left (an action's label is its button),
              // the widget on the right; one line. A slider takes 60% of
              // the line, any other widget what it needs; the label the
              // rest, elided.
              Item {
                id: rowLine
                width: parent.width
                implicitHeight: Math.max(rowLabel.implicitHeight, widget.item ? widget.item.implicitHeight : 0)

                Text {
                  id: rowLabel
                  objectName: "settingLabel-" + settingRow.row.id
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  // As wide as it needs, up to the widget less the help mark.
                  width: Math.min(implicitWidth, Math.max(0, widget.x - Style.space(8) - (helpMark.visible ? helpMark.implicitWidth + Style.space(6) : 0)))
                  visible: settingRow.row.widget !== "action"
                  elide: Text.ElideRight
                  text: settingRow.row.label
                  color: settingRow.greyed ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                // The row has more to say (its reason, its description):
                // shown as a tip while the row has the cursor.
                Text {
                  id: helpMark
                  objectName: "settingHelpMark-" + settingRow.row.id
                  textFormat: Text.PlainText
                  anchors.left: rowLabel.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: rowLabel.visible && settingRow.row.help !== ""
                  text: "?"
                  color: root.faint
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Loader {
                  id: widget
                  objectName: "settingWidget-" + settingRow.row.id
                  readonly property bool isAction: settingRow.row.widget === "action"
                  anchors.left: isAction ? parent.left : undefined
                  anchors.right: isAction ? undefined : parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: settingRow.row.widget === "slider" ? Math.round(parent.width * 0.6)
                    : Math.min(item ? item.implicitWidth : 0, parent.width - Style.space(72))
                  height: item ? item.implicitHeight : 0
                  enabled: !settingRow.greyed
                  sourceComponent: settingRow.row.widget === "slider" ? sliderWidget
                    : (settingRow.row.widget === "switch" ? switchWidget
                      : (settingRow.row.widget === "segmented" ? segmentedWidget
                        : (settingRow.row.widget === "dropdown" ? dropdownWidget
                          : (isAction ? actionWidget : null))))
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                visible: text !== ""
                text: settingRow.row.optionsNote
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // What the row says beyond its label (its reason while greyed,
            // its description), only while it has the cursor (the keyboard's
            // or the pointer's): one tip at a time, drawn over what is under
            // the row in the tooltip's colours, never in the layout, so
            // neither the row nor the card changes size.
            BorderSurface {
              id: helpTip
              objectName: "settingHelpTip-" + settingRow.row.id
              readonly property var tipBorder: Border.localOrSurfaceSpec("tooltip", "border", Commons.Color.tooltip.border,
                                                                          Commons.Color.tooltip.border, Style.normalBorderWidth)
              // Under the row, or above it where under would leave the viewport.
              readonly property bool above: visible && root.viewport !== null
                && settingRow.mapToItem(root.viewport, 0, settingRow.height).y + Style.space(2) + height > root.viewport.height
              x: rowColumn.x
              y: above ? -height - Style.space(2) : parent.height + Style.space(2)
              z: 10
              width: Math.min(helpText.implicitWidth, parent.width - rowColumn.x)
              height: helpText.implicitHeight
              visible: settingRow.onCursor && settingRow.row.help !== ""
              color: Commons.Color.tooltip.background
              borderSpec: tipBorder
              radius: Style.cornerRadius

              // Opaque under the tooltip's fill (a theme may give it alpha):
              // what the tip covers never shows through its words.
              Rectangle {
                anchors.fill: parent
                z: -1
                radius: parent.radius
                color: Commons.Color.background
              }

              Text {
                id: helpText
                objectName: "settingHelp-" + settingRow.row.id
                textFormat: Text.PlainText
                width: Math.min(implicitWidth, settingRow.width - rowColumn.x)
                wrapMode: Text.Wrap
                text: settingRow.row.help
                color: Commons.Color.tooltip.text
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                leftPadding: Border.left(helpTip.tipBorder) + Style.spacing.controlPaddingX
                rightPadding: Border.right(helpTip.tipBorder) + Style.spacing.controlPaddingX
                topPadding: Border.top(helpTip.tipBorder) + Style.spacing.controlPaddingY
                bottomPadding: Border.bottom(helpTip.tipBorder) + Style.spacing.controlPaddingY
              }
            }

            // A switch row owns its click, as the shell's Toggle row does.
            MouseArea {
              anchors.fill: parent
              visible: settingRow.row.widget === "switch"
              hoverEnabled: true
              cursorShape: settingRow.greyed ? Qt.ArrowCursor : Qt.PointingHandCursor
              onEntered: root.cursorRequested("setting", settingRow.row.stop)
              onClicked: if (!settingRow.greyed) Daemon.commitSetting(settingRow.row.id, Model.switchFlip(settingRow.row))
            }

            // int: the slider and its value (what the hand holds while it
            // is held: the shell's PanelSlider shows its own position
            // then). The value text is never faded.
            Component {
              id: sliderWidget
              Item {
                id: sliderBox
                // What the press latched: the set and setting the hand
                // took; "" between drags (a wheel step has none), or
                // `cancelled` once the item shows another one.
                property string heldKey: ""
                readonly property string cancelled: "\u0000"
                readonly property var heldValue: slider.dragging ? Model.clampSetting(settingRow.row, slider.liveValue) : null
                implicitHeight: slider.implicitHeight

                // `released`: no release will follow (the grab is gone).
                function cancelDrag(released) {
                  heldKey = released === true ? "" : cancelled
                  if (!slider.dragging) return
                  slider.dragging = false
                  slider.liveValue = slider.value
                }
                // A move or a release of the drag the hand began on
                // this very setting, or of a wheel step.
                function own() {
                  return heldKey === "" || heldKey === settingRow.rowKey
                }

                // The item now shows another set or setting: the drag
                // ends here and its release writes nothing.
                Connections {
                  target: settingRow
                  function onRowKeyChanged() { if (sliderBox.heldKey !== "" && sliderBox.heldKey !== settingRow.rowKey) sliderBox.cancelDrag() }
                }

                PanelSlider {
                  id: slider
                  objectName: "settingSlider-" + settingRow.row.id
                  bar: root.bar
                  anchors.left: parent.left
                  anchors.right: sliderValue.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: settingRow.greyed ? root.greyedOpacity : 1.0
                  minimum: settingRow.row.min
                  maximum: settingRow.row.max
                  step: settingRow.row.step
                  integer: true
                  value: typeof settingRow.row.value === "number" ? settingRow.row.value : settingRow.row.min
                  onDraggingChanged: {
                    if (dragging) sliderBox.heldKey = settingRow.rowKey
                    root.heldChanged(dragging ? 1 : -1)
                  }
                  onMoved: function(v) { if (sliderBox.own()) Daemon.moveSetting(settingRow.row.id, v) }
                  onReleased: function(v) {
                    var mine = sliderBox.own()
                    sliderBox.heldKey = ""
                    if (mine) Daemon.commitSetting(settingRow.row.id, v)
                  }
                  // A row hidden mid-drag (a collapsed group, another tab,
                  // another camera) loses the mouse grab, and PanelSlider
                  // has no cancel handler: let go here, or the Flickables
                  // would stay locked.
                  onVisibleChanged: if (!visible && dragging) sliderBox.cancelDrag(true)
                  Component.onDestruction: if (dragging) root.heldChanged(-1)
                }
                Text {
                  id: sliderValue
                  objectName: "settingValue-" + settingRow.row.id
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  // Clear of the row's cursor border at the right edge.
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(84)
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideLeft
                  text: sliderBox.heldValue !== null ? Model.settingValueText(settingRow.row, sliderBox.heldValue) : settingRow.row.valueText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            // bool: the shell's row switch, at the right edge; the row
            // owns the click and draws the cursor.
            Component {
              id: switchWidget
              Item {
                implicitWidth: settingSwitch.implicitWidth
                implicitHeight: settingSwitch.implicitHeight
                ToggleSwitch {
                  id: settingSwitch
                  objectName: "settingSwitch-" + settingRow.row.id
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: settingRow.greyed ? root.greyedOpacity : 1.0
                  checked: settingRow.row.checked === true
                  interactive: false
                  cursorRing: false
                  hasCursor: false
                  foreground: root.foreground
                  accent: root.accent
                }
              }
            }

            // enum, few short choices: the shell's ButtonGroup, at the
            // right edge. The panel's chip cursor lights one chip; Enter
            // or Space (or a click) chooses it.
            Component {
              id: segmentedWidget
              Item {
                implicitWidth: choices.implicitWidth
                implicitHeight: choices.implicitHeight
                ButtonGroup {
                  id: choices
                  objectName: "settingChoices-" + settingRow.row.id
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: settingRow.greyed ? root.greyedOpacity : 1.0
                  options: settingRow.row.options
                  value: typeof settingRow.row.value === "string" ? settingRow.row.value : ""
                  focusable: false
                  cursorIndex: settingRow.onCursor && !settingRow.greyed ? root.choiceCursor : -1
                  foreground: root.foreground
                  background: Commons.Color.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onHovered: function(index, isHovered) { if (isHovered) root.choiceHovered(settingRow.row.stop, index) }
                  onChanged: function(value) { Daemon.commitSetting(settingRow.row.id, value) }
                }
              }
            }

            // enum, many or long choices: the shell's Dropdown. Its list
            // takes the keyboard while open; the panel's key catcher gets
            // it back. A list open when the item comes to show another
            // set or setting closes, and its choice writes nothing.
            Component {
              id: dropdownWidget
              Item {
                id: dropdownBox
                property string openKey: ""
                // Wide enough for the longest label (the list's rows are
                // as wide as the box, and a label cut off at "(gone)"
                // would hide the point), never less than 220;
                // the row's loader holds it within the line.
                readonly property real labelsWidth: widestLabel()
                implicitWidth: Math.max(Style.space(220), labelsWidth + 2 * Style.spacing.controlPaddingX + Style.space(36))
                implicitHeight: choiceList.implicitHeight

                // Measured without writing to the metrics (a TextMetrics'
                // text set inside the labelsWidth binding would loop).
                FontMetrics {
                  id: labelProbe
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                function widestLabel() {
                  var options = settingRow.row.options
                  var widest = 0
                  for (var i = 0; i < options.length; i++) {
                    widest = Math.max(widest, labelProbe.advanceWidth(options[i].label))
                  }
                  return widest
                }

                function openList() {
                  choiceList.open()
                }

                Connections {
                  target: settingRow
                  function onRowKeyChanged() { if (choiceList.popupOpen) choiceList.close() }
                }

                Dropdown {
                  id: choiceList
                  objectName: "settingDropdown-" + settingRow.row.id
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: settingRow.greyed ? root.greyedOpacity : 1.0
                  showLabel: false
                  options: settingRow.row.options
                  value: typeof settingRow.row.value === "string" ? settingRow.row.value : ""
                  hasCursor: settingRow.onCursor && !settingRow.greyed
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onHovered: function(isHovered) { if (isHovered) root.cursorRequested("setting", settingRow.row.stop) }
                  onChanged: function(value) {
                    // The Dropdown sets its own value on a choice: bound
                    // to the row's again, so the daemon's word shows.
                    choiceList.value = Qt.binding(function() { return typeof settingRow.row.value === "string" ? settingRow.row.value : "" })
                    if (dropdownBox.openKey === "" || dropdownBox.openKey === settingRow.rowKey)
                      Daemon.commitSetting(settingRow.row.id, value)
                  }
                  onPopupOpenChanged: {
                    dropdownBox.openKey = popupOpen ? settingRow.rowKey : ""
                    if (!popupOpen && root.keyCatcher) root.keyCatcher.forceActiveFocus()
                  }
                }
              }
            }

            // action: a button that runs it once; it draws the cursor.
            Component {
              id: actionWidget
              Item {
                implicitWidth: actionButton.implicitWidth
                implicitHeight: actionButton.implicitHeight
                Button {
                  id: actionButton
                  objectName: "settingAction-" + settingRow.row.id
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: settingRow.greyed ? root.greyedOpacity : 1.0
                  text: settingRow.row.label
                  bordered: true
                  hasCursor: settingRow.onCursor && !settingRow.greyed
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onHovered: function(on) { if (on) root.cursorRequested("setting", settingRow.row.stop) }
                  onClicked: Daemon.runSettingAction(settingRow.row.id)
                }
              }
            }
          }
        }

        // A live, read-only figure of the group (the view's `live`, ""
        // for none): the panel's dim small text, hidden while empty. One
        // line, elided (never wrapped), so it never changes height while
        // shown. It has no Accessible name: it changes up to 4 times a
        // second and a screen reader would announce each change.
        Text {
          objectName: root.namePrefix + "settingsGroupLive-" + groupBlock.group.id
          textFormat: Text.PlainText
          x: root.inset
          width: parent.width - 2 * root.inset
          elide: Text.ElideRight
          visible: text !== ""
          text: groupBlock.group.live || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Rows past the caps or skipped: said, never silently dropped.
        Text {
          objectName: root.namePrefix + "settingsGroupTruncated-" + groupBlock.group.id
          textFormat: Text.PlainText
          x: root.inset
          width: parent.width - 2 * root.inset
          wrapMode: Text.Wrap
          visible: text !== ""
          text: groupBlock.group.truncation
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  Text {
    id: groupsNote
    objectName: root.namePrefix + "settingsTruncated"
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.Wrap
    visible: text !== ""
    text: root.view.truncation
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // ---- "Not available now (n)": one counted line, opened to what cannot
  // run here and why; a Setup button where something is not installed
  Column {
    id: notAvailableBlock
    objectName: root.namePrefix + "notAvailable"
    width: parent.width
    spacing: Style.space(4)
    visible: root.notAvailable.visible === true

    CursorSurface {
      id: notAvailableLine
      objectName: root.namePrefix + "notAvailableLine"
      width: parent.width
      implicitHeight: notAvailableText.implicitHeight + Style.space(6)
      hasCursor: root.hasCursor("unavailable", -1)
      foreground: root.foreground
      fill: root.hoverFill
      Accessible.role: Accessible.Button
      Accessible.name: root.notAvailable.text
      Accessible.description: root.notAvailable.open ? "Expanded" : "Collapsed"

      Text {
        id: notAvailableGlyph
        textFormat: Text.PlainText
        x: root.inset
        width: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        text: root.notAvailable.glyph
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        id: notAvailableText
        objectName: root.namePrefix + "notAvailableText"
        textFormat: Text.PlainText
        anchors.left: notAvailableGlyph.right
        anchors.leftMargin: Style.space(4)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: root.notAvailable.text
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.cursorRequested("unavailable", -1)
        onClicked: root.notAvailableToggled()
      }
    }

    Repeater {
      id: unavailableRepeater
      objectName: root.namePrefix + "notAvailableEntries"
      model: root.notAvailable.open ? root.notAvailable.entries.length : 0
      delegate: Item {
        id: entry
        required property int index
        readonly property var item: root.notAvailable.entries[index] || ({ label: "", reason: "", setup: false })
        readonly property Item button: setupButton
        objectName: root.namePrefix + "notAvailableEntry-" + index
        width: parent ? parent.width : 0
        implicitHeight: Math.max(entryText.implicitHeight, setupButton.visible ? setupButton.implicitHeight : 0) + Style.space(4)

        Column {
          id: entryText
          x: root.inset + Style.space(20)
          anchors.right: setupButton.visible ? setupButton.left : parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            objectName: root.namePrefix + "notAvailableLabel-" + entry.index
            textFormat: Text.PlainText
            width: parent.width
            elide: Text.ElideRight
            text: entry.item.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            objectName: root.namePrefix + "notAvailableReason-" + entry.index
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            text: entry.item.reason
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Button {
          id: setupButton
          objectName: root.namePrefix + "notAvailableSetup-" + entry.index
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: entry.item.setup === true
          text: Model.NOT_AVAILABLE_SETUP_LABEL
          tooltipText: Model.NOT_AVAILABLE_SETUP_TOOLTIP
          bordered: true
          hasCursor: root.hasCursor("unavailable-setup", entry.index)
          foreground: root.foreground
          background: Commons.Color.background
          accent: root.accent
          fontFamily: root.fontFamily
          Accessible.role: Accessible.Button
          Accessible.name: Model.NOT_AVAILABLE_SETUP_LABEL
          Accessible.description: Model.NOT_AVAILABLE_SETUP_TOOLTIP
          onHovered: function(on) { if (on) root.cursorRequested("unavailable-setup", entry.index) }
          onClicked: root.setupRequested(entry.index)
        }
      }
    }

    // The list cut at its cap: said, never silently dropped (the count on
    // the line is the real one).
    Text {
      objectName: root.namePrefix + "notAvailableTruncated"
      textFormat: Text.PlainText
      x: root.inset + Style.space(20)
      width: parent.width - x
      wrapMode: Text.Wrap
      visible: root.notAvailable.open === true && text !== ""
      text: root.notAvailable.note || ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- Reset to defaults: camera-wide, a quiet link at the bottom, right-aligned
  Item {
    width: parent.width
    height: root.view.reset === true ? resetButton.implicitHeight : 0
    visible: root.view.reset === true

    Button {
      id: resetButton
      objectName: root.namePrefix + "settingsReset"
      anchors.right: parent.right
      text: Model.SETTINGS_RESET_LABEL
      tooltipText: Model.SETTINGS_RESET_TOOLTIP
      bordered: false
      fontSize: Style.font.bodySmall
      // A quiet link: its words end on the section's right edge, with the
      // switches and the Setup buttons.
      horizontalPadding: Style.space(2)
      hasCursor: root.hasCursor("reset", -1)
      foreground: root.dim
      accent: root.accent
      fontFamily: root.fontFamily
      Accessible.role: Accessible.Button
      Accessible.name: Model.SETTINGS_RESET_LABEL
      Accessible.description: Model.SETTINGS_RESET_TOOLTIP
      onHovered: function(on) { if (on) root.cursorRequested("reset", -1) }
      onClicked: root.resetRequested()
    }
  }
}
