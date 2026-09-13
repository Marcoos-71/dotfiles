import QtQuick
import qs.Commons

Row {
  id: root

  property var samples: []
  property real maximum: 100
  property color fill: Color.foreground
  property int barCount: 30

  readonly property var visibleSamples: {
    var all = root.samples || []
    return all.length > root.barCount ? all.slice(all.length - root.barCount) : all
  }

  spacing: 1
  height: Style.space(18)

  Repeater {
    model: root.visibleSamples
    Rectangle {
      width: Math.max(1, (root.width - root.spacing * (root.barCount - 1)) / root.barCount)
      height: Math.max(1, root.height * Math.min(1, Math.max(0, modelData / Math.max(1, root.maximum))))
      anchors.bottom: parent.bottom
      color: root.fill
      opacity: 0.85
      radius: 1
    }
  }
}
