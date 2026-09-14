import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Capture.js" as Capture

// Quick capture into the Obsidian vault. Notes are plain markdown files in
// folders, so this writes them directly — no Obsidian plugin, API or running
// instance needed. Nothing is polled: the only process runs when a note is
// actually saved.
BarWidget {
  id: root
  moduleName: "marcos.vault-capture"

  readonly property string vaultPath: Quickshell.env("HOME") + "/Vault"
  readonly property string vaultName: "Vault"

  signal saveFinished(bool ok, string path, string reason)

  function today() {
    var now = new Date()
    var month = ("0" + (now.getMonth() + 1)).slice(-2)
    var day = ("0" + now.getDate()).slice(-2)
    return now.getFullYear() + "-" + month + "-" + day
  }

  function save(categoryKey, title, values, notes) {
    var category = Capture.categoryFor(categoryKey)
    var cleanTitle = Capture.toFilename(title)
    var body = Capture.buildNote(categoryKey, cleanTitle, values, notes, today())
    // Body travels as an argv element, not stdin: Quickshell's Process has no
    // confirmed way to signal EOF on a stdin pipe, and this is exactly how
    // this widget's own save() already passed a multi-line body successfully.
    saveProc.command = ["omarchy-capture", vaultPath + "/" + category.folder, cleanTitle, body]
    saveTimeout.restart()
    saveProc.running = true
  }

  function openInObsidian(relativePath) {
    Quickshell.execDetached([
      "xdg-open",
      "obsidian://open?vault=" + encodeURIComponent(vaultName) + "&file=" + encodeURIComponent(relativePath)
    ])
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
    id: saveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        saveTimeout.stop()
        try {
          var data = JSON.parse(String(text || "{}"))
          root.saveFinished(data.ok === true, data.path || "", data.reason || "")
        } catch (error) {
          root.saveFinished(false, "", "respuesta ilegible de omarchy-capture")
        }
      }
    }
  }

  // A process that fails to start (omarchy-capture missing from PATH) never
  // reaches onStreamFinished — Quickshell's Process has no confirmed public
  // signal for that failure, only exited(), which Qt does not emit when a
  // process never started. A plain timeout is what actually catches it.
  Timer {
    id: saveTimeout
    interval: 4000
    onTriggered: root.saveFinished(false, "", "omarchy-capture no respondió — ¿está en el PATH?")
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
    foreground: "#fab387"  // bar-colors: cluster colour, re-applied by omarchy-bar-colors
    text: "󱘓"
    slotSize: Style.bar.statusSlot
    tooltipText: "Captura rápida al vault"
    onPressed: root.togglePanel()
  }
}
