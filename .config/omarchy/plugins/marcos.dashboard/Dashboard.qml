import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Tokens.js" as T

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
    visible: root.opened || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "marcos-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrim
      anchors.fill: parent
      // The theme's scrim is a 0.5 veil meant to carry the separation alone.
      // With the compositor blurring what is behind, it can recede.
      color: Qt.rgba(Color.menu.scrim.r, Color.menu.scrim.g, Color.menu.scrim.b, T.scrimAlpha)
      opacity: root.opened ? 1 : 0
      // Leaving is quicker than arriving: it is what makes the surface feel
      // responsive rather than slow.
      Behavior on opacity {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
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
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : T.motionScaleFrom
      anchors.verticalCenterOffset: root.opened ? 0 : T.motionRise

      Behavior on opacity {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
      Behavior on scale {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }
      Behavior on anchors.verticalCenterOffset {
        NumberAnimation {
          duration: root.opened ? T.motionNormal : T.motionFast
          easing.type: root.opened ? Easing.OutExpo : Easing.OutCubic
        }
      }

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
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.display * 2
          }
          Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: timeText.bottom
            text: root.spanishDate()
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            // Machine already knows both facts, so the dot asks it rather than
            // duplicating the thresholds here.
            readonly property bool alert: machine.needsAttention

            Rectangle {
              width: Style.space(10)
              height: Style.space(10)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: parent.alert ? "#f9e2af" : "#a6e3a1"
            }
            Text {
              text: parent.alert ? machine.attentionReason : "todo bien"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, T.ruleAlpha)
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
            divider: true
            width: parent.columnWidth
            height: parent.height
            title: "QUÉ ME PERDÍ"
            accent: root.clusterTools

            Missed {
              width: parent.width
              active: root.opened
            }
          }

          Section {
            id: machineSection
            divider: true
            width: parent.columnWidth
            height: parent.height
            title: "MÁQUINA"
            accent: root.clusterResources

            Machine {
              id: machine
              width: parent.width
              active: root.opened
              shell: root.shell
            }
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
