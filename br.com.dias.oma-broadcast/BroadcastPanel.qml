pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The popup's content: state and switch, the daemon's error, the active
// camera, consumers, output mode, live figures while active, and the camera
// list. Everything shown comes out of Model.js already sanitised, and every
// Text here is PlainText as well (tests/check-source.py counts them).
//
// Nothing here changes state directly: a control runs a CLI command through
// the Daemon singleton, and the result arrives on the watch stream.
//
// Keyboard, as in the shell's own panels (PanelKeyCatcher, CursorSurface):
// the first arrow key shows the cursor on the on/off switch; Up/Down (or k/j)
// then walk the switch, each camera row and Next camera; Enter or Space
// activates; Escape closes; Tab moves to the neighbouring panel. The mouse
// moves the same cursor, so only one highlight is ever drawn.
Item {
  id: root

  property QtObject bar: null
  // The popup's open state, from the widget: reopening resets the cursor.
  property bool opened: false

  signal closeRequested()
  signal switchRequested(int direction)

  readonly property Item keyCatcher: catcher
  readonly property var record: Daemon.record
  readonly property bool available: Model.available(record)
  readonly property var visual: Model.visualFor(Model.visualKey(record))
  readonly property var message: Model.unavailableMessage(record)
  readonly property var statsRows: Model.statsRows(record)
  readonly property var cameras: record.cameras
  readonly property string heroMeta: Model.heroMeta(record)
  readonly property string truncation: Model.truncationText(record)

  // ---- the keyboard cursor (one list of stops; see Model.cursorStops) ------
  // Built from the rendered row count, so the cursor and the rows agree.
  readonly property var stops: Model.cursorStops(record, cameraRepeater.count)
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property var currentStop: cursorActive && stops.length > 0
    ? stops[Model.clampCursor(cursorIndex, stops.length)] : null

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

  function moveCursor(dy) {
    if (stops.length === 0 || dy === 0) return
    cursorActive = true
    cursorIndex = Model.clampCursor(Model.clampCursor(cursorIndex, stops.length) + (dy > 0 ? 1 : -1), stops.length)
    scrollCursorIntoView()
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
      elide: Text.ElideRight
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
      root.moveCursor(dy)
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

        // ---- the last control command's failure
        Text {
          objectName: "commandError"
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.Wrap
          visible: text !== ""
          text: Daemon.commandError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
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
