import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

// Barbarian's theme grid — every theme Omarchy can see, as a full-screen grid of previews, with
// Remove on each (Dave, 2026-09-25: "fold this feature into Barbarian"). It is this plugin's
// second entry point, the `overlay` beside the bar widget, so the shell loads it once rather than
// once per bar. Open it with the Themes button (or `t`) in the panel, or
// `omarchy-shell shell toggle tinkerbell.arrange '{}'`: with an overlay in the manifest, the
// shell's own summon and toggle reach this and not the panel, which keeps its own IPC target.
// Kept loaded between summons so ThemeStore can keep hidden themes out of Omarchy's own picker.
Item {
  id: root

  property bool opened: false
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("bin/theme-remover").toString().replace(/^file:\/\//, ""))

  function open(payload) {
    grid.backdropSource = "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background?" + Date.now()
    grid.reset()
    store.message = ""
    store.reload()
    opened = true
    Qt.callLater(grid.focusKeys)
  }

  function close() {
    opened = false
  }

  ThemeStore {
    id: store
    helper: root.helperPath
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "barbarian-themes"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    ThemeGrid {
      id: grid
      anchors.fill: parent
      store: store
      onCloseRequested: root.close()
    }
  }
}
