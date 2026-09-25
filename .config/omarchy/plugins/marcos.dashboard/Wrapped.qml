import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Tokens.js" as T
import "Wrapped.js" as W

Column {
  id: root

  property bool active: false
  property var today: null
  property var dash: null

  readonly property color resources: "#a6e3a1"
  readonly property color warning: "#f9e2af"
  readonly property var stat: dash ? dash.stat : null
  readonly property var achievement: dash ? dash.achievement : null
  readonly property bool unhealthy: dash !== null && !dash.healthOk && dash.healthMessage !== ""

  visible: today !== null || stat !== null || achievement !== null || unhealthy
  spacing: Style.spacing.sm
  topPadding: Style.spacing.md

  // `wrapped today` reads only today's raw log, so it runs once per open like
  // omarchy-agenda. The daily build's file is watched instead: it changes at
  // most once a day, and never while nothing is looking.
  onActiveChanged: {
    if (!active) return
    todayProc.running = true
    dashFile.reload()
  }

  Process {
    id: todayProc
    command: ["wrapped", "today", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.today = W.parseToday(text)
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.today = null }
  }

  FileView {
    id: dashFile
    path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/wrapped/out/dashboard.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.dash = W.parseDashboard(text())
    onLoadFailed: root.dash = null
    onFileChanged: reload()
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
  }

  Text {
    text: "wrapped · hoy"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.2
    topPadding: Style.spacing.sm
    bottomPadding: Style.spacing.xs
  }

  Row {
    visible: root.today !== null
    spacing: Style.spacing.sm
    Text {
      text: root.today ? W.fmtMinutes(root.today.activeMinutes) : ""
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      anchors.baseline: parent.children[0].baseline
      text: "activo"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      rightPadding: Style.spacing.lg
    }
    Text {
      visible: root.today !== null && root.today.keys !== null
      anchors.baseline: parent.children[0].baseline
      text: root.today ? W.fmtCount(root.today.keys) : ""
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      visible: root.today !== null && root.today.keys !== null
      anchors.baseline: parent.children[0].baseline
      text: "teclas"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // Same geometry as the sparkline rows above: label, 150px of bar, value.
  Repeater {
    model: root.today ? root.today.apps : []
    Row {
      spacing: Style.spacing.md
      Text {
        width: Style.space(40)
        text: modelData.icon
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Item {
        width: Style.space(150)
        height: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.fill: parent
          radius: 2
          color: Color.muted
          opacity: 0.25
        }
        Rectangle {
          width: Math.max(2, parent.width * W.share(modelData.minutes, root.today.activeMinutes))
          height: parent.height
          radius: 2
          color: root.resources
          opacity: 0.85
        }
      }
      Text {
        id: appName
        text: modelData.name
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.baseline: appName.baseline
        text: W.fmtMinutes(modelData.minutes)
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    visible: root.stat !== null
    spacing: Style.spacing.md
    topPadding: Style.spacing.md
    Text {
      width: Style.space(40)
      text: root.stat ? String(root.stat.icon || "") : ""
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Column {
      Text {
        text: root.stat
          ? W.fmtCount(root.stat.value) + (root.stat.unit ? " " + root.stat.unit : "") + "  " + (root.stat.label || "")
          : ""
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        text: "dato del día"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    visible: root.achievement !== null
    spacing: Style.spacing.md
    Text {
      width: Style.space(40)
      text: root.achievement ? String(root.achievement.icon || "") : ""
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Column {
      Text {
        text: root.achievement ? String(root.achievement.name || "") : ""
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Row {
        spacing: Style.spacing.xs
        Text {
          text: "último logro"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: text !== ""
          text: root.achievement ? W.tierName(root.achievement.tier) : ""
          color: root.achievement && W.tierColor(root.achievement.tier) !== "" ? W.tierColor(root.achievement.tier) : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          readonly property string day: root.achievement ? W.fmtDay(root.achievement.at) : ""
          visible: day !== ""
          text: "· " + day
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Text {
    visible: root.unhealthy
    width: parent.width
    wrapMode: Text.WordWrap
    topPadding: Style.spacing.sm
    text: "⚠ " + (root.dash ? root.dash.healthMessage : "")
    color: root.warning
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
