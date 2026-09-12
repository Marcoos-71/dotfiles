import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Snapshot health for this machine's actual setup: snapper's timeline timer is
// off, so snapshots come from snap-pac on every pacman transaction. "Healthy"
// therefore means every recent transaction left a snapshot behind, not that a
// schedule ran.
//
// Nothing is polled: snapshots can only change when pacman runs, so the log is
// watched and `snapper --jsonout list` runs once per change.
BarWidget {
  id: root
  moduleName: "marcos.snapper"

  // A pre-snapshot is taken moments before the transaction is logged, so a
  // transaction counts as covered by any snapshot within this window.
  readonly property int coverageWindowSec: 900
  readonly property int dayCount: 7

  // Epoch seconds, newest first.
  property var snapshotTimes: []
  property var transactionTimes: []
  property bool snapperReadable: true

  readonly property real lastSnapshotAt: snapshotTimes.length > 0 ? snapshotTimes[0] : 0
  readonly property real lastTransactionAt: transactionTimes.length > 0 ? transactionTimes[0] : 0

  // Any transaction in the tracked window with no snapshot near it is the
  // failure this widget exists to catch.
  readonly property int uncoveredCount: {
    var uncovered = 0
    for (var i = 0; i < transactionTimes.length; i++) {
      var when = transactionTimes[i]
      var covered = false
      for (var j = 0; j < snapshotTimes.length; j++) {
        if (Math.abs(snapshotTimes[j] - when) <= coverageWindowSec) { covered = true; break }
      }
      if (!covered) uncovered++
    }
    return uncovered
  }

  readonly property bool healthy: snapperReadable && uncoveredCount === 0
  readonly property string icon: !snapperReadable ? "󰆓" : (healthy ? "󰆓" : "󰆓")

  function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() / 1000
  }

  // Newest day last, so the map reads left to right like a calendar.
  function dayBuckets() {
    var buckets = []
    var today = startOfDay(new Date())
    for (var i = dayCount - 1; i >= 0; i--) {
      var from = today - i * 86400
      var to = from + 86400
      var snaps = 0
      var transactions = 0
      for (var s = 0; s < snapshotTimes.length; s++) {
        if (snapshotTimes[s] >= from && snapshotTimes[s] < to) snaps++
      }
      for (var t = 0; t < transactionTimes.length; t++) {
        if (transactionTimes[t] >= from && transactionTimes[t] < to) transactions++
      }
      buckets.push({
        at: from,
        snapshots: snaps,
        transactions: transactions,
        // Red only means something actually went wrong: pacman ran and left no
        // snapshot. A quiet day is not a failure.
        missing: transactions > 0 && snaps === 0
      })
    }
    return buckets
  }

  function humanAge(epochSeconds) {
    if (!epochSeconds) return "nunca"
    var seconds = Math.max(0, Date.now() / 1000 - epochSeconds)
    if (seconds < 3600) return "hace " + Math.max(1, Math.round(seconds / 60)) + " min"
    if (seconds < 86400) return "hace " + Math.round(seconds / 3600) + " h"
    var days = Math.round(seconds / 86400)
    return "hace " + days + (days === 1 ? " día" : " días")
  }

  function sync() {
    if (!snapperProc.running) snapperProc.running = true
  }

  function parsePacmanLog(raw) {
    var text = String(raw || "")
    // Only the tail matters: the seven-day window is a few hundred lines even
    // on a busy machine, and this avoids walking the whole log on every change.
    if (text.length > 200000) text = text.slice(-200000)

    var cutoff = Date.now() / 1000 - dayCount * 86400
    var times = []
    var pattern = /^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:+\-]+)\] \[ALPM\] transaction started/gm
    var match
    while ((match = pattern.exec(text)) !== null) {
      var when = Date.parse(match[1]) / 1000
      if (isFinite(when) && when >= cutoff) times.push(when)
    }
    times.sort(function(a, b) { return b - a })
    root.transactionTimes = times
    root.sync()
  }

  function parseSnapshots(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      root.snapperReadable = false
      return
    }

    var configs = parsed && typeof parsed === "object" ? parsed : {}
    var times = []
    for (var key in configs) {
      var list = configs[key]
      if (!list || !list.length) continue
      for (var i = 0; i < list.length; i++) {
        var date = String(list[i].date || "")
        if (date === "") continue
        // snapper prints local time as "YYYY-MM-DD HH:MM:SS".
        var when = Date.parse(date.replace(" ", "T")) / 1000
        if (isFinite(when)) times.push(when)
      }
    }
    times.sort(function(a, b) { return b - a })
    root.snapshotTimes = times
    root.snapperReadable = true
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Shape contract the bar uses to route summon/hide/toggle to a panel host.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    id: pacmanLog
    path: "/var/log/pacman.log"
    watchChanges: true
    printErrors: false
    onLoaded: root.parsePacmanLog(text())
    onFileChanged: reload()
    onLoadFailed: root.sync()
  }

  Process {
    id: snapperProc
    command: ["snapper", "--jsonout", "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseSnapshots(text) }
    onExited: function(exitCode) { if (exitCode !== 0) root.snapperReadable = false }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    slotSize: Style.bar.statusSlot
    foreground: root.healthy ? (Qt.hsva(((Color.accent.hsvHue * 360 + 58 + 360) % 360) / 360, Math.min(1, Math.max(0, Color.accent.hsvSaturation + -0.1)), Math.min(1, Math.max(0, Color.accent.hsvValue + 0.0)), 1)) : Color.urgent
    opacity: root.snapperReadable ? 1 : 0.45
    tooltipText: !root.snapperReadable
      ? "No se puede leer snapper"
      : (root.uncoveredCount > 0
        ? root.uncoveredCount + " transacción(es) sin snapshot"
        : "Último snapshot " + root.humanAge(root.lastSnapshotAt))
    onPressed: root.togglePanel()
  }
}
