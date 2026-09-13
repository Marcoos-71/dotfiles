import QtQuick
import Quickshell
import Quickshell.Io
import "Metrics.js" as Metrics

Item {
  id: root

  visible: false

  readonly property int historyLimit: 60

  property real cpuPercent: -1
  property real memPercent: -1
  property real memUsedKb: 0
  property real memTotalKb: 0
  property int cpuTemp: -1
  property int gpuTemp: -1
  readonly property int hottest: Math.max(cpuTemp, gpuTemp)

  property string iface: ""
  property real rxRate: -1
  property real txRate: -1

  property var cpuHistory: []
  property var memHistory: []
  property var tempHistory: []
  property var rxHistory: []
  property var txHistory: []

  property string cpuTempPath: ""
  property string gpuTempPath: ""

  property var prevCpu: null
  property real prevRx: -1
  property real prevTx: -1
  property real prevAt: 0
  property real lastResolveAt: 0

  function readSystem() {
    cpuStat.reload()
    var sample = Metrics.parseCpuSample(cpuStat.text())
    if (sample) {
      var percent = Metrics.cpuPercent(root.prevCpu, sample)
      if (percent >= 0) {
        root.cpuPercent = percent
        root.cpuHistory = Metrics.pushSample(root.cpuHistory, percent, root.historyLimit)
      }
      root.prevCpu = sample
    }

    memStat.reload()
    var mem = Metrics.parseMem(memStat.text())
    if (mem) {
      root.memPercent = mem.percent
      root.memUsedKb = mem.usedKb
      root.memTotalKb = mem.totalKb
      root.memHistory = Metrics.pushSample(root.memHistory, mem.percent, root.historyLimit)
    }

    if (root.cpuTempPath !== "") {
      cpuTempFile.reload()
      root.cpuTemp = Metrics.parseTempMilli(cpuTempFile.text())
    }
    if (root.gpuTempPath !== "") {
      gpuTempFile.reload()
      root.gpuTemp = Metrics.parseTempMilli(gpuTempFile.text())
    }
    if (root.hottest >= 0)
      root.tempHistory = Metrics.pushSample(root.tempHistory, root.hottest, root.historyLimit)
  }

  // Interfaces come and go (wifi down, dock plugged in). While none is known
  // the retry is every tick, because at startup the first read loses a race
  // with the FileView load and a 10s wait would blank the graph that long.
  // Once one is known, a failing counter backs off to 10s.
  function resolveIface() {
    var now = Date.now()
    var backoff = root.iface === "" ? 0 : 10000
    if (now - root.lastResolveAt < backoff) return
    root.lastResolveAt = now

    routeFile.reload()
    var found = Metrics.parseDefaultIface(routeFile.text())
    if (found !== root.iface) {
      root.iface = found
      root.prevRx = -1
      root.prevTx = -1
    }
    if (found === "") {
      root.rxRate = -1
      root.txRate = -1
    }
  }

  // An unloaded FileView returns empty, and Number("") is 0 — which would make
  // the next real reading look like a burst of the whole counter. Empty is
  // unknown, not zero.
  function counter(view) {
    view.reload()
    var raw = String(view.text() || "").trim()
    if (raw === "") return -1
    var value = Number(raw)
    return isFinite(value) ? value : -1
  }

  function readNetwork() {
    if (root.iface === "") {
      resolveIface()
      if (root.iface === "") return
    }

    var rx = counter(rxFile)
    var tx = counter(txFile)
    if (rx < 0 || tx < 0) {
      resolveIface()
      return
    }

    var now = Date.now()
    var elapsed = (now - root.prevAt) / 1000
    var rxValue = Metrics.rate(root.prevRx, rx, elapsed)
    var txValue = Metrics.rate(root.prevTx, tx, elapsed)
    if (rxValue >= 0) {
      root.rxRate = rxValue
      root.rxHistory = Metrics.pushSample(root.rxHistory, rxValue, root.historyLimit)
    }
    if (txValue >= 0) {
      root.txRate = txValue
      root.txHistory = Metrics.pushSample(root.txHistory, txValue, root.historyLimit)
    }
    root.prevRx = rx
    root.prevTx = tx
    root.prevAt = now
  }

  FileView { id: cpuStat; path: "/proc/stat"; watchChanges: false; printErrors: false }
  FileView { id: memStat; path: "/proc/meminfo"; watchChanges: false; printErrors: false }
  FileView { id: routeFile; path: "/proc/net/route"; watchChanges: false; printErrors: false }
  FileView { id: cpuTempFile; path: root.cpuTempPath; watchChanges: false; printErrors: false }
  FileView { id: gpuTempFile; path: root.gpuTempPath; watchChanges: false; printErrors: false }

  FileView {
    id: rxFile
    path: root.iface === "" ? "" : "/sys/class/net/" + root.iface + "/statistics/rx_bytes"
    watchChanges: false
    printErrors: false
  }

  FileView {
    id: txFile
    path: root.iface === "" ? "" : "/sys/class/net/" + root.iface + "/statistics/tx_bytes"
    watchChanges: false
    printErrors: false
  }

  Process {
    id: resolveSensors
    running: true
    command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do n=$(cat \"$d/name\" 2>/dev/null); for l in \"$d\"/temp*_label; do [ -e \"$l\" ] || continue; lb=$(cat \"$l\" 2>/dev/null); case \"$n/$lb\" in k10temp/Tctl|zenpower/Tdie|'coretemp/Package id 0') echo \"cpu ${l%_label}_input\";; amdgpu/edge) echo \"gpu ${l%_label}_input\";; esac; done; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var paths = Metrics.parseSensorPaths(text)
        root.cpuTempPath = paths.cpu
        root.gpuTempPath = paths.gpu
        root.readSystem()
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.readSystem()
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.readNetwork()
  }
}
