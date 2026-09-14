import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Tokens.js" as T

// Download/upload throughput straight from sysfs byte counters, with no
// subprocess at all: the default interface comes from /proc/net/route and the
// counters from /sys/class/net/<iface>/statistics. The old waybar setup had a
// second module polling the same counters just to flag heavy transfers; that
// is a state of this widget instead of a second poller.
BarWidget {
  id: root
  moduleName: "marcos.netspeed"

  // Bytes per second over the threshold counts as "a transfer is happening"
  // rather than background chatter. 2 MiB/s is the value the old script used.
  readonly property real transferThreshold: 2 * 1024 * 1024

  // Same lookup as marcos.sysmon. Repeated rather than shared because the two
  // plugins are separate directories with no import path between them.
  property var metrics: null

  function resolveMetrics() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.ensureService === "function")
      root.metrics = root.bar.shell.ensureService("marcos.metrics")
  }

  onBarChanged: resolveMetrics()
  Component.onCompleted: resolveMetrics()

  readonly property bool useService: root.metrics !== null

  property string ownIface: ""
  property real ownRxRate: -1
  property real ownTxRate: -1

  readonly property string iface: useService ? metrics.iface : ownIface
  readonly property real rxRate: useService ? metrics.rxRate : ownRxRate
  readonly property real txRate: useService ? metrics.txRate : ownTxRate

  property real prevRx: -1
  property real prevTx: -1
  property real prevAt: 0
  // Interfaces come and go (wifi down, dock plugged in). Re-resolving is cheap
  // but not free, so a failed read only triggers one retry per interval.
  property real lastResolveAt: 0

  readonly property bool transferring: rxRate + txRate > transferThreshold
  readonly property bool known: rxRate >= 0 && txRate >= 0

  // WidgetButton is Omarchy's and cannot carry our Behavior, so the animation
  // lives on a local property and the button reads that.
  readonly property color targetColor: root.transferring ? Color.accent : "#a6e3a1"
  property color animatedColor: targetColor
  Behavior on animatedColor {
    ColorAnimation { duration: T.motionInstant; easing.type: Easing.OutCubic }
  }
  onTargetColorChanged: animatedColor = targetColor

  function fmtRate(bytesPerSecond) {
    if (bytesPerSecond < 0) return "--"
    if (bytesPerSecond >= 1024 * 1024) return (bytesPerSecond / (1024 * 1024)).toFixed(1) + "M"
    if (bytesPerSecond >= 1024) return Math.round(bytesPerSecond / 1024) + "K"
    return "0K"
  }

  readonly property string label: "󰇚 " + fmtRate(rxRate) + "  󰕒 " + fmtRate(txRate)

  function resolveIface() {
    var now = Date.now()
    if (now - lastResolveAt < 10000) return
    lastResolveAt = now

    routeFile.reload()
    var lines = String(routeFile.text() || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].trim().split(/\s+/)
      // Destination 00000000 is the default route.
      if (parts.length > 1 && parts[1] === "00000000" && parts[0] !== "Iface") {
        if (parts[0] !== ownIface) {
          ownIface = parts[0]
          prevRx = -1
          prevTx = -1
        }
        return
      }
    }
    ownIface = ""
    ownRxRate = -1
    ownTxRate = -1
  }

  function readCounter(view) {
    view.reload()
    var raw = String(view.text() || "").trim()
    if (raw === "") return -1
    var value = Number(raw)
    return isFinite(value) ? value : -1
  }

  function refresh() {
    if (ownIface === "") {
      resolveIface()
      if (ownIface === "") return
    }

    var rx = readCounter(rxFile)
    var tx = readCounter(txFile)
    if (rx < 0 || tx < 0) {
      resolveIface()
      return
    }

    var now = Date.now()
    var elapsed = (now - prevAt) / 1000
    if (prevRx >= 0 && elapsed > 0) {
      // Counters reset when the interface is reinitialised; treat a negative
      // delta as a fresh baseline rather than reporting a nonsense spike.
      ownRxRate = rx >= prevRx ? (rx - prevRx) / elapsed : -1
      ownTxRate = tx >= prevTx ? (tx - prevTx) / elapsed : -1
    }
    prevRx = rx
    prevTx = tx
    prevAt = now
  }

  visible: iface !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView { id: routeFile; path: "/proc/net/route"; watchChanges: false; printErrors: false }
  FileView {
    id: rxFile
    path: root.ownIface === "" ? "" : "/sys/class/net/" + root.ownIface + "/statistics/rx_bytes"
    watchChanges: false
    printErrors: false
  }
  FileView {
    id: txFile
    path: root.ownIface === "" ? "" : "/sys/class/net/" + root.ownIface + "/statistics/tx_bytes"
    watchChanges: false
    printErrors: false
  }

  Timer {
    interval: 2000
    running: !root.useService
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.fmtRate(root.rxRate) : root.label
    // Only the transfer state overrides the color; the idle state inherits the
    // bar's own foreground, which adapts to the wallpaper on a transparent bar.
    foreground: root.animatedColor
    fontSize: Style.font.caption
    horizontalMargin: 8
    tooltipText: root.iface === ""
      ? "Sin conexión"
      : root.iface + "  ·  ↓ " + root.fmtRate(root.rxRate) + "/s  ↑ " + root.fmtRate(root.txRate) + "/s"
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-launch-wifi")
    }
  }
}
