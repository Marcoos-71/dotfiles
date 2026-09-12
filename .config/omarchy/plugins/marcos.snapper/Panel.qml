import QtQuick
import qs.Commons
import qs.Ui

// Presentation only: every value comes from the bar widget that hosts this
// panel, so the panel adds no polling, no process and no state of its own.
Panel {
  id: root
  moduleName: "marcos.snapper"
  ipcTarget: "marcos.snapper"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var buckets: hostWidget ? hostWidget.dayBuckets() : []
  // Sunday-first to match Date.getDay().
  readonly property string dayInitials: "DLMXJVS"

  function cellColor(bucket) {
    if (bucket.missing) return Color.urgent
    if (bucket.snapshots > 0) return Color.accent
    return Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.14)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "Snapshots"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Text {
          text: root.hostWidget
            ? (root.hostWidget.snapperReadable
              ? "Último: " + root.hostWidget.humanAge(root.hostWidget.lastSnapshotAt)
              : "snapper no accesible")
            : ""
          color: Color.popups.text
          opacity: 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          spacing: Style.space(4)

          Repeater {
            model: root.buckets

            Column {
              required property var modelData
              spacing: Style.space(3)

              Rectangle {
                width: Style.space(24)
                height: Style.space(24)
                radius: Style.space(4)
                color: root.cellColor(modelData)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dayInitials.charAt(new Date(modelData.at * 1000).getDay())
                color: Color.popups.text
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: {
            if (!root.hostWidget) return ""
            if (root.hostWidget.uncoveredCount > 0)
              return root.hostWidget.uncoveredCount + " sin snapshot"
            return "Todo cubierto"
          }
          color: root.hostWidget && root.hostWidget.uncoveredCount > 0 ? Color.urgent : Color.popups.text
          opacity: root.hostWidget && root.hostWidget.uncoveredCount > 0 ? 1 : 0.75
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
