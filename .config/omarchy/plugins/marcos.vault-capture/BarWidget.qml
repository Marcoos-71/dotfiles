import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Quick capture into the Obsidian vault. Notes are plain markdown files in
// folders, so this writes them directly — no Obsidian plugin, API or running
// instance needed. Nothing is polled: the only process runs when a note is
// actually saved.
BarWidget {
  id: root
  moduleName: "marcos.vault-capture"

  readonly property string vaultPath: Quickshell.env("HOME") + "/Vault"
  readonly property string vaultName: "Vault"

  // Frontmatter follows the vault's own schemas (see ~/Vault/CLAUDE.md) so the
  // captured notes are queryable by Dataview like any hand-written one.
  readonly property var categories: [
    {
      key: "idea",
      label: "Idea",
      icon: "󰛩",
      folder: "00-Inbox",
      frontmatter: ["type: idea", "tags:", "  - inbox"]
    },
    {
      key: "project",
      label: "Proyecto",
      icon: "󰌢",
      folder: "10-Projects",
      frontmatter: ["type: project", "status: idea", "priority: medium", "tags:", "  - project"]
    },
    {
      key: "manual",
      label: "Manual",
      icon: "󱌣",
      folder: "11-Manual-Projects",
      frontmatter: ["type: project", "status: idea", "priority: medium", "tags:", "  - project", "  - manual"]
    },
    {
      key: "travel",
      label: "Viaje",
      icon: "󰀝",
      folder: "16-Travel",
      frontmatter: ["type: travel", "status: idea", "tags:", "  - travel"]
    }
  ]

  signal noteSaved(string folder)

  function categoryFor(key) {
    for (var i = 0; i < categories.length; i++) {
      if (categories[i].key === key) return categories[i]
    }
    return categories[0]
  }

  function today() {
    var now = new Date()
    var month = ("0" + (now.getMonth() + 1)).slice(-2)
    var day = ("0" + now.getDate()).slice(-2)
    return now.getFullYear() + "-" + month + "-" + day
  }

  // Obsidian titles are filenames, so the text has to survive as one: strip the
  // characters a filename cannot hold and collapse whitespace.
  function toFilename(text) {
    var clean = String(text || "")
      .replace(/[\/\\:*?"<>|]/g, " ")
      .replace(/\s+/g, " ")
      .replace(/^\s+|\s+$/g, "")
    if (clean.length > 80) clean = clean.slice(0, 80).replace(/\s+\S*$/, "")
    return clean === "" ? "Sin titulo" : clean
  }

  function buildNote(category, title) {
    var lines = ["---"]
    for (var i = 0; i < category.frontmatter.length; i++) lines.push(category.frontmatter[i])
    lines.push("created: " + today())
    lines.push("---")
    lines.push("")
    lines.push("# " + title)
    lines.push("")
    return lines.join("\n")
  }

  function save(categoryKey, text) {
    var title = toFilename(text)
    if (title === "") return

    var category = categoryFor(categoryKey)
    // Arguments are passed as argv rather than interpolated into the script, so
    // quotes or shell metacharacters in a note title are just text.
    saveProc.command = [
      "sh", "-c",
      'dir="$1"; base="$2"; body="$3"; mkdir -p "$dir"; f="$dir/$base.md"; n=1; ' +
      'while [ -e "$f" ]; do n=$((n+1)); f="$dir/$base $n.md"; done; printf "%s" "$body" > "$f"',
      "sh",
      vaultPath + "/" + category.folder,
      title,
      buildNote(category, title)
    ]
    saveProc.running = true
    root.noteSaved(category.folder)
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

  Process { id: saveProc }

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
