import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // The bar's cluster palette, repeated here so the same colour means the same
  // kind of thing on both surfaces. omarchy-bar-colors owns the bar's copy;
  // Task 10 teaches it about this file so they cannot drift.
  readonly property color clusterContext: "#89b4fa"
  readonly property color clusterTools: "#fab387"
  readonly property color clusterResources: "#a6e3a1"

  readonly property int cardWidth: Math.min(Style.space(1700), panel.width - Style.space(160))
  readonly property int cardHeight: Math.min(Style.space(820), panel.height - Style.space(120))

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "marcos.dashboard")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function spanishDate() {
    var days = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    var months = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
                  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    var now = clock.date
    return days[now.getDay()] + ", " + now.getDate() + " de " + months[now.getMonth()]
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "marcos-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The component emits semantic signals; Escape arrives as closeRequested.
      onCloseRequested: root.dismiss()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: 1

      // Swallows clicks so hitting the card does not dismiss through the scrim.
      MouseArea { anchors.fill: parent }

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.lg

        Item {
          width: parent.width
          height: timeText.height + dateText.height

          Text {
            id: timeText
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display * 2
          }
          Text {
            id: dateText
            anchors.top: timeText.bottom
            text: root.spanishDate()
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Row {
          width: parent.width
          height: parent.height - timeText.height - dateText.height - Style.spacing.lg * 2
          spacing: Style.spacing.lg

          readonly property int columnWidth: (width - spacing * 2) / 3

          Section {
            id: todaySection
            width: parent.columnWidth
            height: parent.height
            title: "HOY"
            accent: root.clusterContext

            Today {
              width: parent.width
              active: root.opened
            }
          }

          Section {
            id: missedSection
            width: parent.columnWidth
            height: parent.height
            title: "QUÉ ME PERDÍ"
            accent: root.clusterTools
          }

          Section {
            id: machineSection
            width: parent.columnWidth
            height: parent.height
            title: "MÁQUINA"
            accent: root.clusterResources
          }
        }
      }
    }
  }

  // Only ticks while the panel is open, which is the whole reason the overlay
  // is not keepLoaded.
  SystemClock {
    id: clock
    enabled: root.opened
    precision: SystemClock.Minutes
  }
}
