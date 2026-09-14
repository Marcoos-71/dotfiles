import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Calendar.js" as Calendar
import "Tokens.js" as T

Column {
  id: root

  property bool active: false
  property int year: new Date().getFullYear()
  property int month: new Date().getMonth() + 1
  property var eventDays: []
  property date today: new Date()

  readonly property color accent: "#89b4fa"
  readonly property var cells: Calendar.monthGrid(root.year, root.month)

  spacing: Style.spacing.sm

  function reload() {
    monthProc.command = ["omarchy-agenda", "--month",
                         root.year + "-" + String(root.month).padStart(2, "0")]
    monthProc.running = true
  }

  function page(delta) {
    var next = Calendar.shiftMonth(root.year, root.month, delta)
    root.year = next.year
    root.month = next.month
    root.eventDays = []
    reload()
  }

  // Reopening the dashboard lands on the current month: paging is a look
  // around, not a place to be left.
  onActiveChanged: {
    if (!active) return
    root.today = new Date()
    root.year = root.today.getFullYear()
    root.month = root.today.getMonth() + 1
    reload()
  }

  Process {
    id: monthProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.eventDays = (data.ok === true && data.days) ? data.days : []
        } catch (error) {
          root.eventDays = []
        }
      }
    }
  }

  Item {
    width: parent.width
    height: label.implicitHeight

    Text {
      id: label
      text: Calendar.monthLabel(root.year, root.month)
      color: root.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.2
      font.bold: true
    }

    Row {
      anchors.right: parent.right
      spacing: Style.spacing.md

      Repeater {
        model: [{ glyph: "‹", delta: -1 }, { glyph: "›", delta: 1 }]
        Text {
          text: modelData.glyph
          color: arrow.containsMouse ? root.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          Behavior on color { ColorAnimation { duration: T.motionInstant } }
          MouseArea {
            id: arrow
            anchors.fill: parent
            anchors.margins: -Style.spacing.sm
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.page(modelData.delta)
          }
        }
      }
    }
  }

  Grid {
    width: parent.width
    columns: 7
    spacing: 2

    Repeater {
      model: ["L", "M", "X", "J", "V", "S", "D"]
      Text {
        width: (root.width - 12) / 7
        horizontalAlignment: Text.AlignHCenter
        text: modelData
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Repeater {
      model: root.cells
      Item {
        width: (root.width - 12) / 7
        height: dayText.implicitHeight + Style.spacing.sm

        readonly property bool current: modelData.month === 0
        readonly property bool isToday: Calendar.isToday(modelData, root.year, root.month, root.today)
        readonly property bool hasEvent: current && root.eventDays.indexOf(modelData.day) !== -1

        Rectangle {
          anchors.fill: parent
          radius: 3
          color: parent.isToday ? root.accent : "transparent"
        }

        Text {
          id: dayText
          anchors.centerIn: parent
          text: modelData.day
          color: parent.isToday ? Color.menu.background
            : (parent.current ? Color.menu.text : Color.muted)
          opacity: parent.current ? 1 : 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          visible: parent.hasEvent
          width: 3
          height: 3
          radius: 1.5
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          color: parent.isToday ? Color.menu.background : root.accent
        }
      }
    }
  }
}
