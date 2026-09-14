import QtQuick
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "Capture.js" as Capture

// Seven categories, one declarative table (Capture.js) driving all of them:
// this file knows no category by name, only the three field kinds
// (text/number/choice) it renders for whichever one is selected.
Panel {
  id: root
  moduleName: "marcos.vault-capture"
  ipcTarget: "marcos.vault-capture"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string selectedKey: "idea"
  readonly property var currentCategory: Capture.categoryFor(selectedKey)
  readonly property string folderPath: hostWidget ? hostWidget.vaultPath + "/" + currentCategory.folder : ""

  property string statusText: ""
  property bool statusError: false

  // Reads every currently-rendered field control fresh, rather than
  // mirroring their values into a parallel object — the Repeater below
  // already destroys and recreates the right controls per category, so the
  // live UI state is the only source of truth this needs.
  function collectFieldValues() {
    var values = {}
    var fields = root.currentCategory.fields
    for (var i = 0; i < fields.length; i++) {
      var field = fields[i]
      var delegate = fieldsRepeater.itemAt(i)
      var loaded = delegate ? delegate.fieldLoader.item : null
      if (!loaded) {
        values[field.key] = field.kind === "choice" ? field.value : ""
        continue
      }
      values[field.key] = field.kind === "choice" ? loaded.value : loaded.text
    }
    return values
  }

  function commit() {
    var title = titleField.text
    if (title.replace(/\s+/g, "") === "") return
    if (!root.hostWidget) return
    root.hostWidget.save(root.selectedKey, title, root.collectFieldValues(), notesField.text)
  }

  onOpenedChanged: {
    if (opened) {
      root.statusText = ""
      Qt.callLater(function() { titleField.forceActiveFocus() })
    }
  }

  onSelectedKeyChanged: {
    notesField.text = ""
    root.statusText = ""
    // The Repeater below destroys every field from the old category. If one
    // of them held keyboard focus, Qt has nothing left to hand it to —
    // titleField is the one control guaranteed to survive every switch.
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  Connections {
    target: root.hostWidget
    function onSaveFinished(ok, path, reason) {
      if (ok) {
        var name = path.split("/").pop()
        root.statusText = "Guardado: " + name
        root.statusError = false
        titleField.text = ""
        notesField.text = ""
      } else {
        root.statusText = reason || "No se pudo guardar"
        root.statusError = true
      }
    }
  }

  // Shared Enter-saves / Escape-closes handling for every single-line field.
  Component {
    id: textFieldComponent
    TextField {
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true
        }
      }
    }
  }

  Component {
    id: numberFieldComponent
    TextField {
      validator: IntValidator { bottom: 0; top: 9999 }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.commit(); event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true
        }
      }
    }
  }

  Component {
    id: choiceFieldComponent
    ButtonGroup {
      property var fieldOptions: []
      options: fieldOptions
      onChanged: function(v) { value = v }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: titleField
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Every field owns its own Enter/Escape handling; this catcher stays
      // out of the way, same as before this form grew past one field.
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

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: Capture.categories()

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

        PanelSeparator { width: parent.width }

        TextField {
          id: titleField
          width: parent.width
          placeholderText: "Título"
          font.family: Style.font.family

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commit(); event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.close(); event.accepted = true
            }
          }
        }

        Repeater {
          id: fieldsRepeater
          model: root.currentCategory.fields

          Column {
            id: fieldRow
            required property var modelData
            property alias fieldLoader: loader
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: fieldRow.modelData.label + (fieldRow.modelData.hint ? " · " + fieldRow.modelData.hint : "")
              color: Color.popups.text
              opacity: 0.65
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Loader {
              id: loader
              width: parent.width
              sourceComponent: fieldRow.modelData.kind === "choice" ? choiceFieldComponent
                : (fieldRow.modelData.kind === "number" ? numberFieldComponent : textFieldComponent)
              onLoaded: {
                if (fieldRow.modelData.kind === "choice") {
                  item.fieldOptions = fieldRow.modelData.options
                  item.value = fieldRow.modelData.value
                } else {
                  item.text = ""
                  item.width = loader.width
                }
              }
            }
          }
        }

        Text {
          text: "Notas"
          color: Color.popups.text
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        MultilineField {
          id: notesField
          width: parent.width
          height: Style.space(70)
          placeholderText: "Enlaces, por qué te interesa…"

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.close(); event.accepted = true
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                && (event.modifiers & Qt.ControlModifier)) {
              root.commit(); event.accepted = true
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Guardar"
            bordered: true
            fontSize: Style.font.caption
            onClicked: root.commit()
          }

          Text {
            text: "En " + root.currentCategory.folder + " · ⏎ guarda · Ctrl+⏎ en Notas · Esc sale"
            color: Color.popups.text
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          visible: root.statusText !== ""
          text: root.statusText
          color: root.statusError ? "#f38ba8" : "#a6e3a1"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { width: parent.width }

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
              leftAlign: true
              text: String(recentNotes.get(index, "fileBaseName") || "")
              fontSize: Style.font.caption
              onClicked: {
                if (!root.hostWidget) return
                root.hostWidget.openInObsidian(root.currentCategory.folder + "/" + recentNotes.get(index, "fileName"))
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
