import QtQuick
import qs.Commons

Item {
  id: root

  property string title: ""
  property color accent: Color.foreground
  default property alias content: body.data

  implicitHeight: header.height + body.implicitHeight + Style.spacing.md

  Text {
    id: header
    text: root.title
    color: root.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
    font.bold: true
  }

  Column {
    id: body
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.md
    width: parent.width
    spacing: Style.spacing.sm
  }
}
