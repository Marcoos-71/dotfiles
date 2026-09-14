import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.Commons
import "Tokens.js" as T

Column {
  id: root

  property bool active: false
  property var events: []
  property bool agendaOk: true
  property string agendaReason: ""
  property var syncedAt: null

  // Six hours without a sync means vdirsyncer has not run — usually no network.
  // Saying so is the difference between "nothing on today" and "I do not know".
  readonly property bool stale: syncedAt !== null && (Date.now() / 1000 - syncedAt) > 21600

  spacing: Style.spacing.sm

  onActiveChanged: if (active) agendaProc.running = true

  Process {
    id: agendaProc
    command: ["omarchy-agenda"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.events = data.events || []
          root.agendaOk = data.ok === true
          root.agendaReason = data.reason || ""
          root.syncedAt = typeof data.syncedAt === "number" ? data.syncedAt : null
        } catch (error) {
          root.events = []
          root.agendaOk = false
          root.agendaReason = "respuesta ilegible de omarchy-agenda"
        }
      }
    }
  }

  Repeater {
    model: root.events
    Entry {
      lead: modelData.allDay ? "todo el día" : modelData.start
      title: modelData.title
      detail: modelData.location
      leadColor: "#89b4fa"
    }
  }

  Text {
    visible: root.agendaOk && root.events.length === 0
    text: "Nada en la agenda"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    visible: !root.agendaOk
    width: parent.width
    wrapMode: Text.WordWrap
    text: "Agenda sin configurar · omarchy-agenda --setup"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: root.agendaOk && root.stale
    text: "sin sincronizar desde " + Qt.formatDateTime(new Date(root.syncedAt * 1000), "d MMM HH:mm")
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
  }

  Text {
    text: "recordatorios"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.2
    topPadding: Style.spacing.sm
    bottomPadding: Style.spacing.xs
  }

  FolderListModel {
    id: reminderFiles
    folder: "file://" + Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-reminders"
    nameFilters: ["*.message"]
    showDirs: false
    sortField: FolderListModel.Name
  }

  Repeater {
    model: reminderFiles
    Entry {
      lead: "⏰"
      title: fileBaseName
      leadColor: "#89b4fa"
    }
  }

  Text {
    visible: reminderFiles.count === 0
    text: "Sin recordatorios"
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MonthGrid {
    width: parent.width
    active: root.active
  }
}
