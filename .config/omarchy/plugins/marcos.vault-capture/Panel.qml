import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui

// Two jobs in one popup: file a new note into the right folder, and show what
// is already in that folder so a capture lands in context instead of blind.
Panel {
  id: root
  moduleName: "marcos.vault-capture"
  ipcTarget: "marcos.vault-capture"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string selectedKey: "idea"
  readonly property var categories: hostWidget ? hostWidget.categories : []
  readonly property var selected: hostWidget ? hostWidget.categoryFor(selectedKey) : null
  readonly property string folderPath: hostWidget && selected
    ? hostWidget.vaultPath + "/" + selected.folder
    : ""

  function commit() {
    var text = field.text
    if (text.replace(/\s+/g, "") === "") return
    hostWidget.save(selectedKey, text)
    field.text = ""
    // The folder model refreshes on its own once the file lands.
  }

  onOpenedChanged: {
    if (opened) {
      field.text = ""
      field.forceActiveFocus()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: field
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The text field owns Return and typing; only closing stays global.
      blocked: true
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "Captura rápida"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Row {
          spacing: Style.space(6)

          Repeater {
            model: root.categories

            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              selected: root.selectedKey === modelData.key
              bordered: true
              fontSize: Style.font.caption
              onClicked: root.selectedKey = modelData.key
            }
          }
        }

        TextField {
          id: field
          width: parent.width
          placeholderText: root.selected ? "Nueva nota en " + root.selected.folder : ""
          font.family: Style.font.family

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commit()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            }
          }
        }

        PanelSeparator { width: parent.width }

        Text {
          text: root.selected ? "En " + root.selected.folder : ""
          color: Color.popups.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        FolderListModel {
          id: recentNotes
          folder: root.folderPath === "" ? "" : "file://" + root.folderPath
          nameFilters: ["*.md"]
          showDirs: false
          showDotAndDotDot: false
          sortField: FolderListModel.Time
        }

        Column {
          width: parent.width
          spacing: Style.space(2)

          Repeater {
            // Only the newest handful: this is orientation, not a file browser.
            model: Math.min(recentNotes.count, 5)

            Button {
              required property int index
              width: column.width
              text: String(recentNotes.get(index, "fileBaseName") || "")
              fontSize: Style.font.caption
              onClicked: {
                if (!root.hostWidget || !root.selected) return
                root.hostWidget.openInObsidian(root.selected.folder + "/" + recentNotes.get(index, "fileName"))
                root.close()
              }
            }
          }
        }

        Text {
          visible: recentNotes.count === 0
          text: "Sin notas todavía"
          color: Color.popups.text
          opacity: 0.45
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
