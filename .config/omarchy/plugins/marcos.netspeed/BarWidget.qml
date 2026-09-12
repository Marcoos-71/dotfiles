import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

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

  property string iface: ""
  property real rxRate: -1
  property real txRate: -1

  property real prevRx: -1
  property real prevTx: -1
  property real prevAt: 0
  // Interfaces come and go (wifi down, dock plugged in). Re-resolving is cheap
  // but not free, so a failed read only triggers one retry per interval.
  property real lastResolveAt: 0

  readonly property bool transferring: rxRate + txRate > transferThreshold
  readonly property bool known: rxRate >= 0 && txRate >= 0

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
        if (parts[0] !== iface) {
          iface = parts[0]
          prevRx = -1
          prevTx = -1
        }
        return
      }
    }
    iface = ""
    rxRate = -1
    txRate = -1
  }

  function readCounter(view) {
    view.reload()
    var value = Number(String(view.text() || "").trim())
    return isFinite(value) ? value : -1
  }

  function refresh() {
    if (iface === "") {
      resolveIface()
      if (iface === "") return
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
      rxRate = rx >= prevRx ? (rx - prevRx) / elapsed : -1
      txRate = tx >= prevTx ? (tx - prevTx) / elapsed : -1
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

  Timer {
    interval: 2000
    running: true
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
    foreground: root.transferring ? Color.accent : (root.bar ? root.bar.barForeground : Color.foreground)
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
