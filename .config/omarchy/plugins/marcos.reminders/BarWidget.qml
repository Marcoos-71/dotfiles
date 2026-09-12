import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Pending reminders with a live countdown.
//
// `omarchy-reminder show --json` already does the real work (systemd timers,
// message files, remaining time), but it costs a bash + systemctl + jq spawn,
// so it is never polled. Instead the reminder state directory is watched, and
// the countdown between syncs is derived locally from each reminder's absolute
// `at` timestamp. With no reminders set, this widget runs nothing at all.
BarWidget {
  id: root
  moduleName: "marcos.reminders"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"
  readonly property string reminderDir: runtimeDir + "/omarchy-reminders"

  property var reminders: []
  property int count: 0
  // Seconds since epoch, refreshed by the local tick so the countdown recomputes.
  property real nowSec: Date.now() / 1000

  // Driven by the array rather than by `count`: the two are set from the same
  // payload, but a binding that trusts the counter blows up on any payload
  // where they disagree.
  readonly property var nextReminder: reminders && reminders.length > 0 ? reminders[0] : null
  readonly property real nextAt: nextReminder ? Number(nextReminder.at) || 0 : 0
  readonly property int remainingSec: nextAt > 0 ? Math.max(0, Math.round(nextAt - nowSec)) : 0

  function fmtRemaining(seconds) {
    if (seconds >= 3600) {
      var hours = Math.floor(seconds / 3600)
      var mins = Math.round((seconds % 3600) / 60)
      return mins > 0 ? hours + "h " + mins + "m" : hours + "h"
    }
    if (seconds >= 60) return Math.ceil(seconds / 60) + "m"
    return seconds + "s"
  }

  readonly property string label: {
    if (!nextReminder) return "󰔛"
    var text = "󰔛 " + (nextReminder.label || nextReminder.message || "Recordatorio")
      + " " + fmtRemaining(remainingSec)
    if (count > 1) text += "  +" + (count - 1)
    return text
  }

  function sync() {
    if (!syncProc.running) syncProc.running = true
  }

  function applyPayload(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      return
    }
    var list = parsed && parsed.reminders ? parsed.reminders : []
    // Nearest first, so the bar always shows the one that fires next.
    list.sort(function(a, b) { return (Number(a.at) || 0) - (Number(b.at) || 0) })
    root.reminders = list
    root.count = Number(parsed.count) || list.length
    root.nowSec = Date.now() / 1000
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: sync()

  Process {
    id: syncProc
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPayload(text)
    }
  }

  // The state directory only appears once a reminder has been set, so the
  // parent is watched too until it shows up. `clear` empties the directory but
  // leaves it in place, so after the first reminder the inner watch is enough.
  FolderListModel {
    id: dirWatch
    folder: "file://" + root.runtimeDir
    nameFilters: ["omarchy-reminders"]
    showFiles: false
    showDirs: true
    showDotAndDotDot: false
    onCountChanged: root.sync()
  }

  FolderListModel {
    id: reminderWatch
    folder: "file://" + root.reminderDir
    nameFilters: ["*.message"]
    showDirs: false
    showDotAndDotDot: false
    onCountChanged: root.sync()
  }

  // Only ticks while something is pending: it advances the local countdown and
  // re-syncs once the nearest reminder is due, which is also how a fired
  // reminder gets noticed (its timer disappears without touching the folder).
  Timer {
    interval: 1000
    running: root.nextReminder !== null
    repeat: true
    onTriggered: {
      root.nowSec = Date.now() / 1000
      if (root.nextAt > 0 && root.nowSec >= root.nextAt + 1) root.sync()
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    labelVisible: !root.vertical
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    opacity: root.nextReminder ? 1 : 0.45
    fontSize: Style.font.caption
    horizontalMargin: 8
    tooltipText: root.nextReminder ? "Ver recordatorios" : "Sin recordatorios · clic para añadir"
    onPressed: function() {
      Quickshell.execDetached(root.nextReminder
        ? ["omarchy-reminder", "show"]
        : ["omarchy-reminder", "-i"])
    }
  }
}
