pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The popup's content: state and switch, the daemon's error, the live preview
// with its switch and rate, the active camera, consumers, output mode,
// the video effect and the noise removal switch, live figures while active,
// and the camera list. Everything shown comes out of Model.js already
// sanitised, and every Text here is PlainText as well (tests/check-source.py
// counts them).
//
// Nothing here changes state directly: a control runs a CLI command through
// the Daemon singleton, and the result arrives on the watch stream. The
// preview's two controls are preferences: they ask the widget to write its
// layout entry (settingsRequested), and the Preview singleton follows it.
// The preview shows what apps receive: black while the camera is idle or an
// effect loads. Opening the panel never starts the camera.
//
// Keyboard, as in the shell's own panels (PanelKeyCatcher, CursorSurface):
// the first arrow key shows the cursor on the on/off switch; Up/Down (or k/j)
// then walk the switch, the Preview switch, the preview-rate row, the effect
// row, the noise removal switch, each camera row and Next camera; Left/Right
// (or h/l) walk the preview-rate and effect choices; Enter or Space activates;
// Escape closes; Tab moves to the neighbouring panel. The mouse moves the
// same cursor, so only one highlight is ever drawn.
Item {
  id: root

  property QtObject bar: null
  // The popup's open state, from the widget: reopening resets the cursor.
  property bool opened: false

  signal closeRequested()
  signal switchRequested(int direction)
  // A user's change of a preview preference: { previewEnabled } or
  // { previewFps }. Only togglePreview and chooseFps emit it.
  signal settingsRequested(var values)

  readonly property Item keyCatcher: catcher
  readonly property var record: Daemon.record
  readonly property bool available: Model.available(record)
  readonly property var visual: Model.visualFor(Model.visualKey(record))
  readonly property var message: Model.unavailableMessage(record)
  // The last command failure; a path it ends on is drawn on a line of its own.
  readonly property var commandErrorParts: Model.commandErrorParts(Daemon.commandError)
  readonly property var statsRows: Model.statsRows(record)
  readonly property var cameras: record.cameras
  readonly property string heroMeta: Model.heroMeta(record)
  readonly property string truncation: Model.truncationText(record)
  readonly property var effectOptions: Model.effectOptions(record)
  readonly property var effectRows: Model.effectRows(record)
  readonly property var effectHint: Model.effectHint(record)
  readonly property var denoiseRow: Model.denoiseRow(record)
  readonly property var preview: Preview.placeholder
  readonly property bool previewControls: Model.previewControlsShown(record, Preview.pathReason)
  readonly property var fpsOptions: Model.fpsOptions(Preview.fps)

  // ---- the keyboard cursor (one list of stops; see Model.cursorStops) ------
  // Built from the rendered row count, so the cursor and the rows agree.
  readonly property var stops: Model.cursorStops(record, cameraRepeater.count, previewControls)
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var currentStop: cursorActive && stops.length > 0
    ? stops[Model.clampCursor(cursorIndex, stops.length)] : null
  // The effect choice under the cursor while the effect row holds it.
  property int effectCursor: 0
  // The frame-rate choice under the cursor while the frame-rate row holds it.
  property int fpsCursor: 0

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

  readonly property var detailRows: [
    { label: "Camera", value: Model.activeCameraLabel(record) !== "" ? Model.activeCameraLabel(record) : "none" },
    { label: "Consumers", value: record.consumers >= 0 ? String(record.consumers) : Model.UNKNOWN },
    { label: "Output", value: record.outputMode !== "" ? record.outputMode : Model.UNKNOWN }
  ]

  implicitHeight: column.implicitHeight

  function hasCursor(kind, index) {
    return currentStop !== null && currentStop.kind === kind
      && (kind !== "camera" || currentStop.index === index)
  }

  function setCursor(kind, index) {
    var i = Model.stopIndex(stops, kind, index)
    if (i < 0) return
    cursorActive = true
    cursorIndex = i
  }

  // The effect row takes the cursor on the choice under the mouse.
  function setEffectCursor(index) {
    effectCursor = Model.clampCursor(index, Model.EFFECTS.length)
    setCursor("effect", -1)
  }

  function setFpsCursor(index) {
    fpsCursor = Model.clampCursor(index, Model.PREVIEW_FPS_CHOICES.length)
    setCursor("fps", -1)
  }

  function moveCursor(dy) {
    if (stops.length === 0 || dy === 0) return
    cursorActive = true
    cursorIndex = Model.clampCursor(Model.clampCursor(cursorIndex, stops.length) + (dy > 0 ? 1 : -1), stops.length)
    // Arriving on the effect or frame-rate row lands on the current choice,
    // as the shell's button groups do.
    if (currentStop && currentStop.kind === "effect")
      effectCursor = Math.max(0, Model.effectIndex(record.effectKey))
    if (currentStop && currentStop.kind === "fps")
      fpsCursor = Math.max(0, Model.PREVIEW_FPS_CHOICES.indexOf(Preview.fps))
    scrollCursorIntoView()
  }

  // Left/Right: only the effect and frame-rate rows lay out horizontally.
  function moveCursorH(dx) {
    if (dx === 0 || !currentStop) return
    if (currentStop.kind === "effect")
      effectCursor = Model.clampCursor(effectCursor + (dx > 0 ? 1 : -1), Model.EFFECTS.length)
    else if (currentStop.kind === "fps")
      fpsCursor = Model.clampCursor(fpsCursor + (dx > 0 ? 1 : -1), Model.PREVIEW_FPS_CHOICES.length)
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

  // Same rule as the switch: nothing while a command's result is still to
  // come, nothing for the current effect or one that cannot be requested
  // (Replace without a background image). The value sent is a word of
  // Model.EFFECTS, never text from the daemon.
  function chooseEffect(index) {
    var option = root.effectOptions[index]
    if (!option || !option.selectable || !root.available || Daemon.commandBusy) return false
    return Daemon.setEffect(option.value)
  }

  // Same rule as the effect choices: nothing while a command's result is
  // still to come, nothing while the daemon does not report noise removal.
  // The value sent is the flip of the reported state, as a boolean.
  function toggleDenoise() {
    if (!root.available || !root.denoiseRow.visible || Daemon.commandBusy) return false
    return Daemon.setDenoise(root.record.denoise !== true)
  }

  // Same rule as the bar's left click: no toggle while a command's result is
  // still to come (ToggleSwitch's `busy` swallows the click the same way).
  function toggleSwitch() {
    if (!root.available || Daemon.commandBusy) return false
    return Daemon.setEnabled(!root.record.enabled)
  }

  function activateCursor() {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "switch") toggleSwitch()
    else if (stop.kind === "preview") togglePreview()
    else if (stop.kind === "fps") chooseFps(fpsCursor)
    else if (stop.kind === "effect") chooseEffect(effectCursor)
    else if (stop.kind === "denoise") toggleDenoise()
    else if (stop.kind === "camera") {
      var row = cameraRepeater.itemAt(stop.index)
      if (row) row.choose()
    } else if (stop.kind === "next") Daemon.nextCamera()
  }

  function scrollItemIntoView(item) {
    if (!item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(flick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > flick.contentY + flick.height - margin)
        flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  function scrollCursorIntoView() {
    var stop = currentStop
    if (!stop) return
    if (stop.kind === "switch") flick.contentY = 0
    else if (stop.kind === "preview") scrollItemIntoView(previewLine)
    else if (stop.kind === "fps") scrollItemIntoView(fpsLine)
    else if (stop.kind === "effect") scrollItemIntoView(effectChoices)
    else if (stop.kind === "denoise") scrollItemIntoView(denoiseLine)
    else if (stop.kind === "camera") scrollItemIntoView(cameraRepeater.itemAt(stop.index))
    else scrollItemIntoView(nextButton)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    flick.contentY = 0
  }
  onStopsChanged: if (cursorIndex >= stops.length) cursorIndex = Math.max(0, stops.length - 1)

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

    Flickable {
      id: flick
      objectName: "panelFlick"
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
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
              busy: Daemon.commandBusy
              hasCursor: root.hasCursor("switch", -1)
              foreground: root.foreground
              accent: root.accent
              onHovered: function(on) { if (on) root.setCursor("switch", -1) }
              onToggled: root.toggleSwitch()

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

        // ---- live preview: what apps receive. The first section, under the
        // header and any error (an error stays right under the on/off switch).
        Column {
          id: previewBlock
          objectName: "previewBlock"
          width: parent.width
          spacing: Style.space(10)
          visible: root.preview.mode !== "hidden"

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "PREVIEW"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // One line instead of the frame area wherever no frame is shown and
          // none is starting: the preview cannot work here (a daemon before
          // revision 5, an unusable XDG_RUNTIME_DIR), it ended with an error,
          // or the camera is off or idle, or the preview is off.
          Text {
            objectName: "previewNote"
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.Wrap
            visible: root.preview.mode === "note"
            text: root.preview.mode === "note" ? root.preview.text : ""
            color: root.preview.error ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // 16:9, as the frames are (480x270): only for frames and while the
          // preview starts. The theme's fill while it starts; black only
          // behind a frame.
          Rectangle {
            id: previewFrame
            objectName: "previewFrame"
            width: parent.width
            height: Math.round(width * 9 / 16)
            visible: root.preview.mode === "box" || root.preview.mode === "image"
            color: root.preview.mode === "image" ? "black" : root.hoverFill
            border.width: 1
            border.color: root.faint
            clip: true

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
              fillMode: Image.PreserveAspectFit
              cache: false
              asynchronous: true
              retainWhileLoading: true
              sourceSize.width: 480
              sourceSize.height: 270
              visible: root.opened && root.preview.mode === "image"
              source: root.opened && root.preview.mode === "image" ? Preview.frameSource : ""
            }
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
          }

          // The Preview switch: laid out as the noise removal row.
          Item {
            id: previewLine
            objectName: "previewRow"
            width: parent.width
            visible: root.previewControls
            implicitHeight: Math.max(previewLabel.implicitHeight, previewSwitch.implicitHeight)

            Text {
              id: previewLabel
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: previewSwitch.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: "Preview"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            ToggleSwitch {
              id: previewSwitch
              objectName: "previewToggle"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: Preview.switchOn
              hasCursor: root.hasCursor("preview", -1)
              foreground: root.foreground
              accent: root.accent
              onHovered: function(on) { if (on) root.setCursor("preview", -1) }
              onToggled: root.togglePreview()

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
            width: parent.width
            visible: root.previewControls
            implicitHeight: Math.max(fpsLabel.implicitHeight, fpsChoices.implicitHeight)

            Text {
              id: fpsLabel
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: fpsChoices.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: "Preview rate"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
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

        // ---- status
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.available

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "STATUS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: root.detailRows
            delegate: InfoRow {
              required property var modelData
              label: modelData.label
              value: modelData.value
            }
          }
        }

        // ---- video effect: the choices, then what the effect uses
        Column {
          objectName: "effectBlock"
          width: parent.width
          spacing: Style.space(10)
          visible: root.available

          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "EFFECT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: effectChoices
            objectName: "effectChoices"
            spacing: Style.spacing.md

            Repeater {
              id: effectRepeater
              objectName: "effectRepeater"
              model: root.effectOptions
              delegate: Button {
                id: effectChip
                required property var modelData
                required property int index
                objectName: "effectChoice-" + modelData.value
                text: modelData.label
                tooltipText: modelData.tooltip
                selected: modelData.selected
                // One highlight: the panel cursor, which the mouse moves too.
                hasCursor: root.hasCursor("effect", -1) && root.effectCursor === index
                bordered: true
                // Shown, but faded, when it cannot be chosen (Replace with
                // no background image, or every choice when the CLI or
                // the daemon predates effects); the hint below says why.
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

          // The hint and its command read as one instruction: the same
          // spacing as the unavailable block's pair.
          Column {
            objectName: "effectHintBlock"
            width: parent.width
            spacing: Style.space(6)
            visible: root.effectHint.text !== "" || root.effectHint.commandText !== ""

            Text {
              objectName: "effectHint"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.Wrap
              visible: text !== ""
              text: root.effectHint.text
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            // Shown, never run.
            Text {
              objectName: "effectHintCommand"
              textFormat: Text.PlainText
              width: parent.width
              elide: Text.ElideRight
              visible: text !== ""
              text: root.effectHint.commandText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Noise removal: a stage that runs with any effect, so a switch of
          // its own, not a choice above; laid out as the rows around it, with
          // the hero switch's control. Not drawn while the daemon does not
          // report it (an old CLI or daemon): an off switch would claim a
          // state nobody reported.
          Item {
            id: denoiseLine
            objectName: "denoiseRow"
            width: parent.width
            visible: root.denoiseRow.visible
            implicitHeight: Math.max(denoiseLabel.implicitHeight, denoiseSwitch.implicitHeight)

            Text {
              id: denoiseLabel
              objectName: "denoiseLabel"
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: denoiseSwitch.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: root.denoiseRow.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            ToggleSwitch {
              id: denoiseSwitch
              objectName: "denoiseToggle"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.denoiseRow.checked
              busy: Daemon.commandBusy
              hasCursor: root.hasCursor("denoise", -1)
              foreground: root.foreground
              accent: root.accent
              onHovered: function(on) { if (on) root.setCursor("denoise", -1) }
              onToggled: root.toggleDenoise()

              PanelToolTip {
                visible: denoiseSwitch.containsMouse
                text: root.denoiseRow.tooltip
                fontFamily: root.fontFamily
              }
            }
          }
        }

        // ---- live figures, only while active
        Column {
          objectName: "statsBlock"
          width: parent.width
          spacing: Style.space(10)
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

        // ---- cameras
        Column {
          objectName: "camerasBlock"
          width: parent.width
          spacing: Style.space(6)
          visible: root.available

          PanelSeparator { foreground: root.foreground }
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

        // ---- actions: shown only when there is a camera to move to
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
          onHovered: function(on) { if (on) root.setCursor("next", -1) }
          onClicked: Daemon.nextCamera()
        }
      }
    }
  }
}
