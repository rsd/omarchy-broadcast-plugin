pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The camera's settings, drawn generically from Model.settingsView: whatever
// the daemon publishes, in its groups and order, through one widget per type:
//   int     the shell's PanelSlider, with the value and its unit
//   bool    the shell's ToggleSwitch (as the shell's panels draw a row switch;
//           the row owns its click)
//   enum    a row of the shell's Buttons (its ButtonGroup) up to
//           Model.SEGMENTED_MAX_OPTIONS short choices, else its Dropdown
//   action  a Button
// A group is a header that opens and closes, one open at a time (memory only:
// the panel holds the choice, Model.openGroupId), or, where the view says it
// is not collapsible (the Effect tab's), a plain heading over rows that are
// always shown; a row the daemon greys out
// keeps its label, value and the daemon's reason legible, only its control is
// faded, and it takes no input. Nothing here knows any setting: no id is
// named, every label, unit, reason and choice comes from the view, already
// sanitised by Model.js (markup characters removed), and every Text is
// PlainText (tests/check-source.py counts them).
//
// Layout: the section title with Reset to defaults on its line, and the
// note, on top; the groups in a Flickable that scrolls only when the screen
// has no room for them (`room`; it then shows a scroll bar and a fade at the
// edge with more); the groups' note under it. Reset is never scrolled away.
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
  // Put before the objectName of the section's own parts (settingsTitle,
  // settingsFlick, ...), so that two sections in one panel are told apart.
  property string namePrefix: ""
  // Model.settingsView(record, open, drafts), or Model.effectSettingsView
  // (the Effect tab's: no title, no Reset, groups that stay open).
  property var view: ({ visible: false, hint: "", note: "", groups: [], truncation: "", reset: false, rowCount: 0, setKey: "",
                        title: "", collapsible: true })
  // The panel's current stop ({ kind, index }) or null, and its chip cursor.
  property var cursorStop: null
  property int choiceCursor: -1
  // Where the keyboard goes back to once a dropdown's list closes.
  property Item keyCatcher: null
  // The most this section may take on the screen (the card's room below its
  // top); 0: no cap. Past it the groups scroll here, alone.
  property real room: 0
  // Sliders held anywhere in the panel: the Flickable never takes a drag then.
  property int slidersHeld: 0
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
  // A slider was grabbed (+1) or let go (-1): the panel's Flickables must
  // not take the drag over.
  signal heldChanged(int delta)

  // The left inset of headings and rows: none in the Effect tab, where they
  // line up with the panel's section headers and choices.
  readonly property real inset: view.collapsible === false ? 0 : Style.space(6)
  readonly property Item flick: settingsFlick
  readonly property Item resetItem: resetButton

  spacing: Style.space(8)
  visible: view.visible

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

  // Enter or Space on a dropdown row: its list opens and takes the keyboard
  // (the shell Dropdown's own keys: Up/Down or j/k walk, Enter chooses,
  // Escape closes); the panel's key catcher gets it back on close.
  function openChoices(stop) {
    var item = rowItem(stop)
    return item ? item.openChoices() : false
  }

  // The height everything but the groups' Flickable takes.
  readonly property real pinnedHeight: sectionTitle.height
    + (noteText.visible ? noteText.height + spacing : 0)
    + (hintText.visible ? hintText.height + spacing : 0)
    + (groupsNote.visible ? groupsNote.height + spacing : 0)
    + (groupsBox.visible ? spacing : 0)

  // The section's title, and on its line Reset to defaults: camera-wide,
  // so it sits with the title, right-aligned, apart from any setting's own
  // button, pinned above the groups and never scrolled away.
  Item {
    id: sectionTitle
    width: parent.width
    // Nothing to say (the Effect tab's section): no line, no gap.
    visible: root.view.title !== "" || root.view.reset === true
    height: visible ? Math.max(titleText.implicitHeight, resetButton.visible ? resetButton.implicitHeight : 0) : 0

    PanelSectionHeader {
      id: titleText
      objectName: root.namePrefix + "settingsTitle"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.view.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Button {
      id: resetButton
      objectName: root.namePrefix + "settingsReset"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.view.reset === true
      text: Model.SETTINGS_RESET_LABEL
      tooltipText: Model.SETTINGS_RESET_TOOLTIP
      bordered: true
      hasCursor: root.hasCursor("reset", -1)
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      Accessible.role: Accessible.Button
      Accessible.name: Model.SETTINGS_RESET_LABEL
      Accessible.description: Model.SETTINGS_RESET_TOOLTIP
      onHovered: function(on) { if (on) root.cursorRequested("reset", -1) }
      onClicked: root.resetRequested()
    }
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

  Item {
    id: groupsBox
    width: parent.width
    height: settingsFlick.height
    visible: root.view.groups.length > 0

    Flickable {
      id: settingsFlick
      objectName: root.namePrefix + "settingsFlick"
      readonly property real fullHeight: groupsColumn.implicitHeight
      readonly property real roomLeft: root.room > 0 ? Math.max(Style.space(160), root.room - root.pinnedHeight) : fullHeight
      readonly property bool moreBelow: interactive && contentY + height < contentHeight - 1
      width: parent.width
      height: Math.min(fullHeight, roomLeft)
      contentWidth: width
      contentHeight: fullHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height + 0.5 && root.slidersHeld === 0
      // At rest too while it scrolls: the cue that more is there.
      ScrollBar.vertical: ScrollBar {
        objectName: root.namePrefix + "settingsScrollBar"
        policy: settingsFlick.contentHeight > settingsFlick.height + 0.5 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
      }

      Column {
        id: groupsColumn
        // Clear of the scroll bar while there is one.
        width: settingsFlick.width - (settingsFlick.contentHeight > settingsFlick.height + 0.5 ? Style.space(12) : 0)
        // Headers and rows carry their own padding: no gap between them.
        spacing: 0

        Repeater {
          id: groupRepeater
          objectName: root.namePrefix + "settingsGroupRepeater"
          model: root.view.groups.length

          delegate: Column {
            id: groupBlock
            required property int index
            readonly property var group: root.view.groups[index] || ({ id: "", label: "", expanded: false, glyph: "", rows: [], truncation: "" })
            readonly property Item header: groupHeader
            objectName: root.namePrefix + "settingsGroup-" + group.id
            width: groupsColumn.width
            spacing: Style.space(1)

            // Not collapsible (the Effect tab): a gap above each group after
            // the first, so the groups read as sections.
            Item {
              width: parent.width
              height: Style.space(8)
              visible: root.view.collapsible === false && groupBlock.index > 0
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
                readonly property var row: groupBlock.group.rows[index] || ({ id: "", type: "", widget: "", label: "", enabled: false,
                                                                              reason: "", value: null, valueText: "", min: 0, max: 1,
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
                // greyed row): hovering it moves the cursor there. A switch
                // row's MouseArea below does the same; elsewhere the widget
                // is the target and reports its own hover.
                HoverHandler {
                  enabled: settingRow.row.widget === "slider" || settingRow.greyed
                  onHoveredChanged: if (hovered) root.cursorRequested("setting", settingRow.row.stop)
                }

                Column {
                  id: rowColumn
                  x: root.inset
                  y: Style.space(2)
                  width: parent.width - 2 * root.inset
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
                      anchors.right: widget.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      visible: settingRow.row.widget !== "action"
                      elide: Text.ElideRight
                      text: settingRow.row.label
                      color: settingRow.greyed ? root.dim : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
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

                  // Why the daemon greys it out: the panel's hint style.
                  Text {
                    objectName: "settingReason-" + settingRow.row.id
                    textFormat: Text.PlainText
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: settingRow.greyed && text !== ""
                    text: settingRow.row.reason
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
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

                // A switch row owns its click, as the shell's Toggle row does.
                MouseArea {
                  anchors.fill: parent
                  visible: settingRow.row.widget === "switch"
                  hoverEnabled: true
                  cursorShape: settingRow.greyed ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onEntered: root.cursorRequested("setting", settingRow.row.stop)
                  onClicked: if (!settingRow.greyed) Daemon.commitSetting(settingRow.row.id, settingRow.row.value !== true)
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
                      checked: settingRow.row.value === true
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

                    TextMetrics {
                      id: labelProbe
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    function widestLabel() {
                      var options = settingRow.row.options
                      var widest = 0
                      for (var i = 0; i < options.length; i++) {
                        labelProbe.text = options[i].label
                        widest = Math.max(widest, labelProbe.advanceWidth)
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
    }

    // More below the edge: the bottom fades into the card.
    Rectangle {
      objectName: root.namePrefix + "settingsMoreBelow"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(28)
      visible: settingsFlick.moreBelow
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 1.0; color: Commons.Color.popups.background }
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
}
