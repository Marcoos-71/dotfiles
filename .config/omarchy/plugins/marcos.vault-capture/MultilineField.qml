import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Multi-line sibling of qs.Ui.TextField, styled the same way. TextField
// itself can't do this — it's single-line — so the notes box needed its own
// component rather than reusing one.
TextArea {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property bool hasCursor: false

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  wrapMode: TextEdit.Wrap
  hoverEnabled: true
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: verticalPadding + Border.top(_borderSpec)
  bottomPadding: verticalPadding + Border.bottom(_borderSpec)

  background: BorderSurface {
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }
}
