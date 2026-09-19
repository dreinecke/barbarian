import QtQuick
import Quickshell
import "barbarian" as Barb

// Barbarian's panel in the nested Hyprland, on its headless output (which renders although the
// host never shows the nested window). `nested panel` runs this with a throwaway HOME.
ShellRoot {
  PanelWindow {
    screen: Quickshell.screens.find(function(sc) { return sc.name === "BARBTEST" }) || Quickshell.screens[0]
    anchors { top: true; right: true }
    implicitWidth: 40
    implicitHeight: 30
    color: "#202020"
    Barb.Panel {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
