import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Column {
  id: root

  property bool active: false
  property var shell: null
  property var metrics: null

  property string diskFree: "--"
  property real diskFreePercent: -1
  property var snapshotDays: []

  readonly property color resources: "#a6e3a1"

  // The header dot reads these rather than repeating the thresholds. Snapshot
  // coverage is deliberately not part of it: "a pacman transaction with no
  // snapshot" needs the pacman.log parsing that marcos.snapper owns, and
  // duplicating it here would be a second source of truth.
  readonly property bool diskLow: diskFreePercent >= 0 && diskFreePercent < 10
  readonly property bool tempHigh: metrics !== null && metrics.hottest >= 65
  readonly property bool needsAttention: diskLow || tempHigh
  readonly property string attentionReason: tempHigh ? "temperatura alta" : "disco casi lleno"

  spacing: Style.spacing.sm

  onActiveChanged: {
    if (!active) return
    if (root.shell && typeof root.shell.ensureService === "function")
      root.metrics = root.shell.ensureService("marcos.metrics")
    diskProc.running = true
    snapshotProc.running = true
  }

  function fmtRate(bytesPerSecond) {
    if (bytesPerSecond < 0) return "--"
    if (bytesPerSecond >= 1024 * 1024) return (bytesPerSecond / (1024 * 1024)).toFixed(1) + " MB/s"
    if (bytesPerSecond >= 1024) return Math.round(bytesPerSecond / 1024) + " KB/s"
    return "0 KB/s"
  }

  function fmtGb(kb) {
    return (kb / 1024 / 1024).toFixed(1)
  }

  Process {
    id: diskProc
    command: ["sh", "-c", "df --output=avail,pcent -h / | tail -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        root.diskFree = parts[0] || "--"
        // df prints percent USED; free space is the complement.
        var used = Number(String(parts[1] || "").replace("%", ""))
        root.diskFreePercent = isFinite(used) ? 100 - used : -1
      }
    }
  }

  // snapper's own timeline is off; snapshots come from snap-pac on each pacman
  // transaction, so a day with no snapshot only matters if something was
  // installed that day. The week strip shows presence, not health.
  Process {
    id: snapshotProc
    command: ["sh", "-c", "snapper --jsonout list 2>/dev/null || echo '{}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var days = [false, false, false, false, false, false, false]
        try {
          var data = JSON.parse(String(text || "{}"))
          var list = data.root || []
          var now = new Date()
          for (var i = 0; i < list.length; i++) {
            if (!list[i].date) continue
            var when = new Date(list[i].date.replace(" ", "T"))
            var ago = Math.floor((now - when) / 86400000)
            // The cells are labelled with weekday names, so a snapshot belongs
            // to its own weekday, not to its distance from today. getDay() is
            // Sunday-first; the strip starts on Monday.
            if (ago >= 0 && ago < 7) days[(when.getDay() + 6) % 7] = true
          }
        } catch (error) {
          // Leave the week empty rather than inventing snapshots.
        }
        root.snapshotDays = days
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md
    Text {
      text: "CPU"
      color: Color.muted
      width: Style.space(40)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Sparkline {
      width: Style.space(150)
      samples: root.metrics ? root.metrics.cpuHistory : []
      maximum: 100
      fill: root.resources
    }
    Text {
      text: root.metrics && root.metrics.cpuPercent >= 0 ? Math.round(root.metrics.cpuPercent) + "%" : "--"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md
    Text {
      text: "RAM"
      color: Color.muted
      width: Style.space(40)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Sparkline {
      width: Style.space(150)
      samples: root.metrics ? root.metrics.memHistory : []
      maximum: 100
      fill: root.resources
    }
    Text {
      text: root.metrics && root.metrics.memTotalKb > 0
        ? root.fmtGb(root.metrics.memUsedKb) + "/" + root.fmtGb(root.metrics.memTotalKb) + " GB"
        : "--"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.md
    Text {
      text: "TMP"
      color: Color.muted
      width: Style.space(40)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Sparkline {
      width: Style.space(150)
      samples: root.metrics ? root.metrics.tempHistory : []
      maximum: 100
      fill: root.resources
    }
    Text {
      text: root.metrics && root.metrics.hottest >= 0 ? root.metrics.hottest + "°" : "--"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  Text {
    text: "↓ " + root.fmtRate(root.metrics ? root.metrics.rxRate : -1)
      + "     ↑ " + root.fmtRate(root.metrics ? root.metrics.txRate : -1)
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    topPadding: Style.spacing.md
  }

  Text {
    text: "Disco   " + root.diskFree + " libres"
    color: Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: !root.metrics
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Servicio de métricas no disponible"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Row {
    spacing: Style.spacing.sm
    topPadding: Style.spacing.md
    Repeater {
      model: ["L", "M", "X", "J", "V", "S", "D"]
      Column {
        spacing: 2
        Text {
          text: modelData
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          width: Style.space(14)
          height: Style.space(14)
          radius: 3
          color: (root.snapshotDays[index] === true) ? root.resources : Color.muted
          opacity: (root.snapshotDays[index] === true) ? 0.9 : 0.25
        }
      }
    }
  }
}
