import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CPU / RAM / temperatures, read from procfs and sysfs with no periodic
// subprocess: /proc/stat and /proc/meminfo give CPU and memory, and the hwmon
// temp inputs give the two temperatures. The only process this widget ever
// spawns is a single sensor-path resolution at startup.
BarWidget {
  id: root
  moduleName: "marcos.sysmon"

  // Sensors are resolved by hwmon name + temp label rather than by index,
  // because hwmon numbering is assigned at boot and reorders. Fallbacks cover
  // Intel (coretemp) and zenpower so a CPU swap doesn't silently blank this.
  property string cpuTempPath: ""
  property string gpuTempPath: ""

  property real cpuPercent: -1
  property real memPercent: -1
  property int cpuTemp: -1
  property int gpuTemp: -1

  // /proc/stat is cumulative since boot, so usage is the delta between two
  // readings; the first reading only establishes the baseline.
  property real prevBusy: -1
  property real prevTotal: -1

  readonly property int hottest: Math.max(cpuTemp, gpuTemp)
  readonly property bool warm: hottest >= 65 && hottest < 80
  readonly property bool hot: hottest >= 80

  function fmtPercent(value) {
    return value < 0 ? "--" : Math.round(value) + "%"
  }

  function fmtTemps() {
    if (cpuTemp < 0 && gpuTemp < 0) return ""
    var cpu = cpuTemp < 0 ? "--" : cpuTemp + "°"
    var gpu = gpuTemp < 0 ? "--" : gpuTemp + "°"
    return "  󰜏 " + cpu + "/" + gpu
  }

  readonly property string label: root.vertical
    ? fmtPercent(cpuPercent)
    : "󰻠 " + fmtPercent(cpuPercent) + "  󰅛 " + fmtPercent(memPercent) + fmtTemps()

  function readCpu() {
    cpuStat.reload()
    var line = String(cpuStat.text() || "").split("\n")[0]
    if (!line.startsWith("cpu ")) return

    var parts = line.trim().split(/\s+/)
    var total = 0
    for (var i = 1; i < parts.length; i++) total += Number(parts[i]) || 0
    // idle + iowait are the two non-busy buckets.
    var idle = (Number(parts[4]) || 0) + (Number(parts[5]) || 0)
    var busy = total - idle

    if (prevTotal >= 0 && total > prevTotal) {
      cpuPercent = Math.max(0, Math.min(100, (busy - prevBusy) / (total - prevTotal) * 100))
    }
    prevBusy = busy
    prevTotal = total
  }

  function readMem() {
    memStat.reload()
    var text = String(memStat.text() || "")
    var totalMatch = text.match(/MemTotal:\s+(\d+)/)
    var availMatch = text.match(/MemAvailable:\s+(\d+)/)
    if (!totalMatch || !availMatch) return

    var total = Number(totalMatch[1])
    var avail = Number(availMatch[1])
    if (total > 0) memPercent = (1 - avail / total) * 100
  }

  function readTemps() {
    if (cpuTempPath !== "") {
      cpuTempFile.reload()
      var cpuRaw = Number(String(cpuTempFile.text() || "").trim())
      cpuTemp = isFinite(cpuRaw) && cpuRaw > 0 ? Math.round(cpuRaw / 1000) : -1
    }
    if (gpuTempPath !== "") {
      gpuTempFile.reload()
      var gpuRaw = Number(String(gpuTempFile.text() || "").trim())
      gpuTemp = isFinite(gpuRaw) && gpuRaw > 0 ? Math.round(gpuRaw / 1000) : -1
    }
  }

  function refresh() {
    readCpu()
    readMem()
    readTemps()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView { id: cpuStat; path: "/proc/stat"; watchChanges: false; printErrors: false }
  FileView { id: memStat; path: "/proc/meminfo"; watchChanges: false; printErrors: false }
  FileView { id: cpuTempFile; path: root.cpuTempPath; watchChanges: false; printErrors: false }
  FileView { id: gpuTempFile; path: root.gpuTempPath; watchChanges: false; printErrors: false }

  Process {
    id: resolveSensors
    running: true
    command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); for l in \"$d\"/temp*_label; do [ -e \"$l\" ] || continue; lb=$(cat \"$l\" 2>/dev/null); case \"$n/$lb\" in k10temp/Tctl|zenpower/Tdie|'coretemp/Package id 0') echo \"cpu ${l%_label}_input\";; amdgpu/edge) echo \"gpu ${l%_label}_input\";; esac; done; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].trim().split(/\s+/)
          if (parts.length !== 2) continue
          if (parts[0] === "cpu" && root.cpuTempPath === "") root.cpuTempPath = parts[1]
          else if (parts[0] === "gpu" && root.gpuTempPath === "") root.gpuTempPath = parts[1]
        }
        root.refresh()
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      console.log("SYSMON label=[" + root.label + "] width=" + button.implicitWidth
        + " cpuPath=" + root.cpuTempPath + " gpuPath=" + root.gpuTempPath)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    foreground: root.hot ? Color.urgent : (root.warm ? warnColor.value : Color.foreground)
    fontSize: Style.font.caption
    horizontalMargin: 8
    tooltipText: "CPU " + root.fmtPercent(root.cpuPercent)
      + "  ·  RAM " + root.fmtPercent(root.memPercent)
      + (root.cpuTemp >= 0 ? "  ·  CPU " + root.cpuTemp + "°C" : "")
      + (root.gpuTemp >= 0 ? "  ·  GPU " + root.gpuTemp + "°C" : "")
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    }
  }

  // The shell's Color singleton exposes no warning role, so the warm tier is
  // read straight from the active theme. Themes disagree on key names (Nord
  // has `yellow`, Catppuccin has `color3`), hence both, falling back to the
  // normal text color rather than inventing one.
  QtObject {
    id: warnColor
    property color value: Color.foreground
  }

  FileView {
    id: themeColors
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: warnColor.value = parseWarn(text())
    onFileChanged: reload()
    onLoadFailed: warnColor.value = Color.foreground
  }

  function parseWarn(raw) {
    var match = String(raw || "").match(/^\s*(?:yellow|color3)\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
    return match ? match[1] : Color.foreground
  }
}
