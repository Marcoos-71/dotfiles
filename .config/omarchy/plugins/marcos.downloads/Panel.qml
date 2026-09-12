import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "marcos.downloads"
  ipcTarget: "marcos.downloads"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function fmtSpeed(bytesPerSecond) {
    if (!bytesPerSecond || bytesPerSecond < 1024) return "0K"
    if (bytesPerSecond >= 1024 * 1024) return (bytesPerSecond / (1024 * 1024)).toFixed(1) + "M"
    return Math.round(bytesPerSecond / 1024) + "K"
  }

  onOpenedChanged: if (opened && hostWidget) hostWidget.refreshTorrents()

  // The only polling in this widget, and it stops the moment the panel closes.
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: if (root.hostWidget) root.hostWidget.refreshTorrents()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "Descargas"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        FolderListModel {
          id: files
          // Guarded: an empty path makes the underlying watcher complain.
          folder: root.hostWidget ? "file://" + root.hostWidget.downloadsDir : ""
          showDirs: false
          showDotAndDotDot: false
          sortField: FolderListModel.Time
        }

        Repeater {
          model: Math.min(files.count, 5)

          Button {
            required property int index
            width: column.width
            leftAlign: true
            fontSize: Style.font.caption
            text: String(files.get(index, "fileName") || "")
            onClicked: {
              root.hostWidget.openPath(root.hostWidget.downloadsDir + "/" + files.get(index, "fileName"))
              root.close()
            }
          }
        }

        Text {
          visible: files.count === 0
          text: "~/Downloads vacío"
          color: Color.popups.text
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { width: parent.width }

        Text {
          text: "qBittorrent"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Text {
          visible: !root.hostWidget || !root.hostWidget.torrentsAvailable
          text: "No disponible"
          color: Color.popups.text
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.hostWidget && root.hostWidget.torrentsAvailable ? root.hostWidget.downloading : []

          Column {
            required property var modelData
            width: column.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              elide: Text.ElideRight
              text: String(modelData.name || "")
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Rectangle {
                width: parent.width - speedLabel.width - Style.space(6)
                height: Style.space(4)
                radius: height / 2
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.15)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                  width: parent.width * Math.max(0, Math.min(1, Number(modelData.progress) || 0))
                  height: parent.height
                  radius: parent.radius
                  color: Color.accent
                }
              }

              Text {
                id: speedLabel
                text: root.fmtSpeed(Number(modelData.dlspeed) || 0) + "/s"
                color: Color.popups.text
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        Text {
          visible: root.hostWidget && root.hostWidget.torrentsAvailable
            && root.hostWidget.downloading.length === 0
          text: "Nada descargando"
          color: Color.popups.text
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.hostWidget && root.hostWidget.torrentsAvailable
            ? root.hostWidget.completed.slice(0, 3)
            : []

          Text {
            required property var modelData
            width: column.width
            elide: Text.ElideRight
            text: "󰄬 " + String(modelData.name || "")
            color: Color.popups.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
