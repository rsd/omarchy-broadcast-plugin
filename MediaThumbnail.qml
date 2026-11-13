import QtQuick
import qs.Commons
import "Model.js" as Model

// A gallery image's thumbnail: the panel's Background row and the setup
// dialog's Away image row. A 16:9 frame with the image cropped to fill it,
// decoded off the UI thread at twice its drawn size; a faint image glyph
// (Model.GLYPH_IMAGE) when there is none, it does not load, or not yet.
// `source` is only ever Model.mediaImageSource of a checked path ("" for
// none), and the owner passes "" while it is not shown, so nothing is
// decoded for a closed panel or dialog.
Rectangle {
  id: root

  property string source: ""
  // The accessible name (the owner's label and the image's name).
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
  Accessible.name: root.name

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
    font.pixelSize: Style.font.display
  }
}
