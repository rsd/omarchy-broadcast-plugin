import QtQuick

// Stands in for qs.Ui's OverlayWindow in the harness. The real one is a
// fullscreen layer-shell window, which has no backend offscreen; the setup
// dialog's logic and its content do not need one. It fills the dialog's own
// item, which the harness puts in its window at the size of a small screen,
// so the keys the harness sends reach the dialog and its card can be grabbed.
// An Item has no layer-shell object to attach, so the dialog's
// `WlrLayershell.namespace` line is taken out of the copy the harness loads
// (run-harness.sh).
Item {
  id: root

  // Whether the overlay is showing, as the real one's.
  property bool shown: false

  anchors.fill: parent
  visible: shown
}
