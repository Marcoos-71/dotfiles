import QtQuick
import qs.Commons
import "Tokens.js" as T

Item {
  id: root

  property string title: ""
  property color accent: Color.foreground
  property bool divider: false
  default property alias content: body.data

  implicitHeight: header.height + body.implicitHeight + Style.spacing.md

  Rectangle {
    visible: root.divider
    width: 1
    x: -Style.spacing.lg
    height: parent.height
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
  }

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
