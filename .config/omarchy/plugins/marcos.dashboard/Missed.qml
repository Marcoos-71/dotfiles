import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.Commons

Column {
  id: root

  property bool active: false
  readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"

  spacing: Style.spacing.sm

  function clearAll() {
    clearProc.command = ["sh", "-c", 'rm -f -- "$1"/*.json', "sh", root.historyDir]
    clearProc.running = true
  }

  Process { id: clearProc }

  FolderListModel {
    id: history
    folder: "file://" + root.historyDir
    nameFilters: ["*.json"]
    showDirs: false
    sortField: FolderListModel.Time
    sortReversed: false
  }

  Repeater {
    model: history
    Entry {
      id: entry
      required property string filePath
      lead: "●"
      leadColor: "#fab387"
      title: notification.appName
      detail: notification.summary

      QtObject {
        id: notification
        property string appName: "?"
        property string summary: ""
      }

      FileView {
        path: entry.filePath
        watchChanges: false
        printErrors: false
        onLoaded: {
          try {
            var data = JSON.parse(text())
            // `app` is the sending program - "notify-send", or empty - so it is
            // the least useful thing to lead with. The headline is `summary`,
            // with `body` underneath, which is how the notification was written.
            notification.appName = data.summary || data.app || data.appName || "?"
            notification.summary = data.body || ""
          } catch (error) {
            notification.appName = "?"
          }
        }
      }
    }
  }

  Text {
    visible: history.count === 0
    text: "Nada que revisar"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: history.count > 0
    text: "limpiar"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    topPadding: Style.spacing.sm

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.clearAll()
    }
  }

  Text {
    text: "── en marcha ──"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    topPadding: Style.spacing.md
  }

  FolderListModel {
    id: downloads
    folder: "file://" + Quickshell.env("HOME") + "/Downloads"
    showDirs: false
    sortField: FolderListModel.Time
    sortReversed: false
  }

  Repeater {
    model: Math.min(downloads.count, 3)
    Entry {
      lead: "⬇"
      leadColor: "#fab387"
      title: downloads.get(index, "fileName")
    }
  }

  Text {
    visible: downloads.count === 0
    text: "Sin descargas recientes"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
