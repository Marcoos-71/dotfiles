import QtQuick
import qs.Commons

Item {
  id: root

  property string lead: ""
  property string title: ""
  property string detail: ""
  property color leadColor: Color.muted

  width: parent ? parent.width : 0
  implicitHeight: Math.max(leadText.implicitHeight, titleText.implicitHeight + detailText.implicitHeight)

  Text {
    id: leadText
    // Sized for "HH:MM" so times line up, but an all-day event's "todo el día"
    // is wider and would otherwise draw straight over the title.
    width: Math.max(Style.space(64), implicitWidth)
    text: root.lead
    color: root.leadColor
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    id: titleText
    anchors.left: leadText.right
    anchors.leftMargin: Style.spacing.md
    anchors.right: parent.right
    text: root.title
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  Text {
    id: detailText
    anchors.left: titleText.left
    anchors.top: titleText.bottom
    anchors.right: parent.right
    visible: root.detail !== ""
    height: visible ? implicitHeight : 0
    text: root.detail
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}
