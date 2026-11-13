import QtQuick
import qs.Commons
import "Model.js" as Model

// A gallery image's thumbnail: the panel's Background row, the setup
// dialog's Backgrounds rows and its Away image row. A 16:9 frame with the
// image cropped to fill it, decoded off the UI thread at twice its drawn
// size; a faint image glyph (Model.GLYPH_IMAGE) when there is none, it does
// not load, or not yet. For a video (`video`) the image is its poster and a
// small video glyph (Model.GLYPH_FILE_VIDEO) sits in the bottom-left corner,
// over the poster or the placeholder alike. `source` is only ever
// Model.mediaImageSource of a checked path ("" for none), and the owner
// passes "" while it is not shown, so nothing is decoded for a closed panel
// or dialog.
Rectangle {
  id: root

  property string source: ""
  // A video: the badge is drawn.
  property bool video: false
  // The accessible name (the owner's label and the image's name); a
  // video's says so (", video").
  property string name: ""
  property color fill: "transparent"
  property color faint: "transparent"
  property string fontFamily: ""
  width: Style.space(64)
  height: Math.round(width * 9 / 16)
  color: root.fill
  border.width: 1
  border.color: root.faint
  clip: true
  Accessible.role: Accessible.Graphic
  Accessible.name: root.video ? root.name + ", " + Model.MEDIA_VIDEO_WORD : root.name

  Image {
    id: thumbImage
    objectName: root.objectName + "Image"
    anchors.fill: parent
    anchors.margins: 1
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: root.width * 2
    sourceSize.height: root.height * 2
    visible: status === Image.Ready
    source: root.source
  }
  // No image, or one that did not load (or not yet).
  Text {
    id: thumbGlyph
    objectName: root.objectName + "Placeholder"
    anchors.centerIn: parent
    visible: thumbImage.status !== Image.Ready
    textFormat: Text.PlainText
    text: Model.GLYPH_IMAGE
    color: root.faint
    font.family: root.fontFamily
    // Scaled to the frame, so a small one keeps it clear of the video badge.
    font.pixelSize: Math.min(Style.font.display, Math.floor(root.height * 0.6))
  }
  // The video badge: the glyph on a small dark plate, legible on any poster.
  Rectangle {
    objectName: root.objectName + "VideoBadge"
    visible: root.video
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(3)
    width: badgeGlyph.implicitWidth + Style.space(6)
    height: badgeGlyph.implicitHeight + Style.space(2)
    radius: Style.space(3)
    color: Qt.rgba(0, 0, 0, 0.6)
    Text {
      id: badgeGlyph
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: Model.GLYPH_FILE_VIDEO
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
