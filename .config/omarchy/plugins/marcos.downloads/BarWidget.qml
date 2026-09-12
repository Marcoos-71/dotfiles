import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Recent downloads and torrent activity.
//
// The bar icon costs nothing: the torrent query only runs while the panel is
// open (the pattern Omarchy's own power panel uses), and ~/Downloads is watched
// rather than polled. Credentials never appear here — omarchy-qbittorrent reads
// them from a 600 file and prints JSON.
BarWidget {
  id: root
  moduleName: "marcos.downloads"

  readonly property string downloadsDir: Quickshell.env("HOME") + "/Downloads"

  property var downloading: []
  property var completed: []
  property bool torrentsAvailable: false

  function refreshTorrents() {
    if (!torrentProc.running) torrentProc.running = true
  }

  function applyTorrents(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      root.torrentsAvailable = false
      return
    }
    root.torrentsAvailable = parsed.available === true
    root.downloading = parsed.downloading || []
    root.completed = parsed.completed || []
  }

  function openPath(path) {
    Quickshell.execDetached(["xdg-open", path])
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

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Process {
    id: torrentProc
    command: ["omarchy-qbittorrent"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyTorrents(text) }
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
    foreground: Qt.hsva(((Color.accent.hsvHue * 360 + 58 + 360) % 360) / 360, Math.min(1, Math.max(0, Color.accent.hsvSaturation + -0.1)), Math.min(1, Math.max(0, Color.accent.hsvValue + 0.0)), 1)  // bar-colors: cluster colour, re-applied by omarchy-bar-colors
    text: "󰅧"
    slotSize: Style.bar.statusSlot
    tooltipText: "Descargas"
    onPressed: root.togglePanel()
  }
}
