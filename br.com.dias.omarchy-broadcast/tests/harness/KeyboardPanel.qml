import QtQuick
import qs.Commons as Commons

// Stands in for qs.Ui's KeyboardPanel in the harness. The real one is a layer
// shell window, which has no backend offscreen; the widget's logic and its
// content do not need one. Same properties and helpers the widget uses,
// including lazy `content`, drawn as a card on the popups background so the
// harness can grab it to a PNG.
Item {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property bool open: false
  property bool centerOnBar: false
  property Item focusTarget: null
  property int padding: 14
  property int contentWidth: 340
  property int contentHeight: 200

  property Component content: null
  property bool contentRequested: false
  readonly property Item loadedContent: contentLoader.item
  readonly property real loadedContentHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0

  function ensureContent() {
    if (content) contentRequested = true
    return contentLoader.item
  }
  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }
  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    return Math.round(cap !== undefined && Number(cap) > 0 ? Math.min(desired, Number(cap)) : desired)
  }
  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(padding * 2, (Number(implicitHeight) || 0) + padding * 2)
    return Math.round(cap !== undefined && Number(cap) > 0 ? Math.min(desired, Number(cap)) : desired)
  }

  // As the real one: the content is built on open and its focus target
  // takes the keyboard (PanelKeyCatcher then sees the keys).
  onOpenChanged: if (open) {
    if (content) contentRequested = true
    Qt.callLater(function() { if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus() })
  }

  // The real popup is its own surface: drawn beside the bar strip here, not
  // inside the widget, so a grab of the strip shows only the icons.
  parent: anchorItem && anchorItem.Window.window ? anchorItem.Window.window.contentItem : null
  x: 10
  y: 50
  width: contentWidth
  height: contentHeight
  visible: open

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.popups.background
    border.width: 1
    border.color: Commons.Color.popups.border
  }

  Loader {
    id: contentLoader
    x: root.padding
    y: root.padding
    width: root.contentWidth - root.padding * 2
    height: root.contentHeight - root.padding * 2
    active: !!root.content && (root.open || root.contentRequested)
    sourceComponent: root.content
  }
}
