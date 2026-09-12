import QtQuick
import qs.Commons
import qs.Ui

// A launcher, not a monitor: no timer and no polling, because nothing about
// pacman's cache needs watching between the moments you decide to clean it.
BarWidget {
  id: root
  moduleName: "marcos.cleanup"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: Qt.hsva(((Color.accent.hsvHue * 360 + 58 + 360) % 360) / 360, Math.min(1, Math.max(0, Color.accent.hsvSaturation + -0.1)), Math.min(1, Math.max(0, Color.accent.hsvValue + 0.0)), 1)  // bar-colors: cluster colour, re-applied by omarchy-bar-colors
    text: "󰃢"
    slotSize: Style.bar.statusSlot
    tooltipText: "Limpiar caché y paquetes huérfanos"
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation ~/.local/bin/omarchy-cleanup.sh")
    }
  }
}
