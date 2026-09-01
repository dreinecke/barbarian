import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Arrange: reorder the bar's RIGHT section from a panel, because dragging the real bar
// icons in place would mean reaching into the shell's private layout code (not ours, and
// overwritten on every Omarchy update). Dave, 2026-08-31, offered this as the sturdy
// version of "hold hyper and drag the bar" — "The word :)".
//
// How it works: the panel reads shell.json's right section — plus the hidden entries
// parked in bar-hidden.json — into one list; rows are DRAGGED with the mouse or nudged
// with keys, and the eye button (or `x`) hides/shows a row (Dave, 2026-09-01: Bluetooth
// is "noise/clutter 99% of the time but occasionally I want" it back). Files are written
// ONCE, when the panel closes (Enter, click-away) — Escape throws the changes away. The
// write goes through bin/bar-arrange-apply, which moves whole entries so per-widget
// settings (the clock's formats) travel untouched — a hidden entry is parked in the
// sidecar with its settings and position, never deleted — and the bar hot-reloads.
//
// The widget itself draws NOTHING on the bar (zero width) — it exists so the shell loads
// this panel and gives it an IPC target. HYPER+B toggles it (bindings.lua).
Panel {
  id: root

  moduleName: "tinkerbell.arrange"
  ipcTarget: "tinkerbell.arrange"

  readonly property string applyScript:
    Qt.resolvedUrl("bin/bar-arrange-apply").toString().replace(/^file:\/\//, "")
  // This widget must never list (or reorder away) itself.
  readonly property string selfId: "tinkerbell.arrange"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string iconGrip: "\uF0C9"
  readonly property string iconCheck: "\uF00C"
  readonly property string iconX: "\uF00D"
  readonly property string iconEye: "\uF06E"
  readonly property string iconEyeSlash: "\uF070"

  property int cursor: 0
  property bool dirty: false
  property bool cancelled: false
  property string loadError: ""

  // Nothing on the bar: the panel is the whole widget.
  implicitWidth: 0
  implicitHeight: 0

  // Friendly names for the ids Dave actually has; anything unknown falls back to its id's
  // last segment so a future widget still gets a readable row.
  function prettyName(wid) {
    var known = {
      "omarchy.tray": "System tray",
      "omarchy.agents": "Agents",
      "omarchy.bluetooth": "Bluetooth",
      "omarchy.network": "Network",
      "omarchy.audio": "Audio",
      "omarchy.monitor": "System monitor",
      "tinkerbell.mail": "Mail",
      "tinkerbell.messages": "Messages",
      "jankeesvw.downloads": "Downloads",
      "jankeesvw.time-machine": "Time Machine",
      "jankeesvw.notification-center": "Notifications",
      "omarchy.indicators": "Indicators",
      "omarchy.clock": "Clock",
      "omarchy.keyboard-layout": "Keyboard layout",
      "omarchy.system-update": "System update",
      "omarchy.power": "Power",
      "omarchy.weather": "Weather",
      "omarchy.workspaces": "Workspaces",
      "omarchy.spacer": "Spacer"
    }
    if (known[wid] !== undefined) return known[wid]
    var tail = String(wid).split(".").pop().replace(/-/g, " ")
    return tail.charAt(0).toUpperCase() + tail.slice(1)
  }

  ListModel { id: lm }

  function loadRows(text) {
    lm.clear()
    loadError = ""
    try {
      // Two files ride one cat (see readProc): shell.json, a marker, bar-hidden.json.
      var parts = text.split("---BARHIDDEN---")
      var layout = JSON.parse(parts[0]).bar.layout.right
      var rows = []
      for (var i = 0; i < layout.length; i++) {
        var wid = String(layout[i].id || "")
        if (wid === "" || wid === selfId) continue
        rows.push({ wid: wid, label: prettyName(wid), hid: false })
      }
      // Hidden entries come back at (or near) the spot they were hidden from.
      var parked = []
      try { parked = JSON.parse(parts[1] || "{}").right || [] } catch (e2) {}
      parked.sort(function(a, b) { return (a.index || 0) - (b.index || 0) })
      for (var p = 0; p < parked.length; p++) {
        var pw = String((parked[p].entry || {}).id || "")
        if (pw === "" || pw === selfId) continue
        var at = Math.min(Math.max(0, parked[p].index || 0), rows.length)
        rows.splice(at, 0, { wid: pw, label: prettyName(pw), hid: true })
      }
      for (var r = 0; r < rows.length; r++) lm.append(rows[r])
    } catch (e) {
      loadError = "Could not read the bar layout file."
    }
    cursor = 0
  }

  function toggleHidden(i) {
    if (i < 0 || i >= lm.count) return
    lm.setProperty(i, "hid", !lm.get(i).hid)
    dirty = true
  }

  function moveItem(from, to) {
    if (from === to || from < 0 || to < 0 || from >= lm.count || to >= lm.count) return
    lm.move(from, to, 1)
    cursor = to
    dirty = true
  }

  function moveCursor(delta) {
    if (lm.count === 0) return
    cursor = Math.max(0, Math.min(lm.count - 1, cursor + delta))
  }

  function apply() {
    if (applyProc.running) return
    var argv = [applyScript]
    for (var i = 0; i < lm.count; i++)
      argv.push(lm.get(i).wid + (lm.get(i).hid ? ":hidden" : ""))
    applyProc.command = argv
    applyProc.running = true
  }

  function acceptAndClose() { close() }
  function cancelAndClose() { cancelled = true; close() }

  onOpenedChanged: {
    if (opened) {
      dirty = false
      cancelled = false
      readProc.command = ["sh", "-c",
        "cat \"$HOME/.config/omarchy/shell.json\"; echo ---BARHIDDEN---; cat \"$HOME/.config/omarchy/bar-hidden.json\" 2>/dev/null || echo '{}'"]
      readProc.running = true
    } else if (dirty && !cancelled) {
      apply()
    }
  }

  Process {
    id: readProc
    stdout: StdioCollector {
      onStreamFinished: root.loadRows(text)
    }
  }

  Process {
    id: applyProc
  }

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Escape CANCELS (nothing written); Enter and click-away APPLY.
      onCloseRequested: root.cancelAndClose()
      onActivateRequested: root.acceptAndClose()
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      // x (PanelKeyCatcher's delete key) hides/shows the selected row.
      onDeleteRequested: root.toggleHidden(root.cursor)
      // j/k walk, J/K carry the selected row with them (vim senses: J down, K up).
      onTextKey: function(t) {
        if (t === "j") root.moveCursor(1)
        else if (t === "k") root.moveCursor(-1)
        else if (t === "J") root.moveItem(root.cursor, root.cursor + 1)
        else if (t === "K") root.moveItem(root.cursor, root.cursor - 1)
      }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Math.max(headText.implicitHeight, applyButton.height)

          PanelSectionHeader {
            id: headText
            anchors.left: parent.left
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "Right side of the bar"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              id: applyButton
              iconText: root.iconCheck
              tooltipText: "Apply order"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.iconSmall
              onClicked: root.acceptAndClose()
            }

            PanelActionButton {
              iconText: root.iconX
              tooltipText: "Cancel"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.iconSmall
              onClicked: root.cancelAndClose()
            }
          }
        }

        PanelSeparator { width: parent.width }

        Item {
          width: parent.width
          height: root.loadError !== "" ? errText.implicitHeight + Style.space(6) : 0
          visible: root.loadError !== ""

          Text {
            id: errText
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.loadError
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: bar ? bar.urgent : Color.urgent
          }
        }

        ListView {
          id: list
          width: parent.width
          clip: true
          model: lm
          interactive: false
          spacing: 0

          readonly property int slotHeight: Style.space(34)
          readonly property int cap: Math.max(Style.space(200),
            panel.availableCardHeight - panel.verticalContentInset - Style.space(70))
          height: Math.min(lm.count * slotHeight, cap)

          move: Transition { NumberAnimation { properties: "y"; duration: 110 } }
          moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 110 } }
          displaced: Transition { NumberAnimation { properties: "y"; duration: 110 } }

          delegate: Item {
            id: wrap
            required property var model
            required property int index

            width: list.width
            height: list.slotHeight
            z: dragArea.drag.active ? 10 : 0

            Rectangle {
              id: card
              width: wrap.width
              height: wrap.height - Style.space(4)
              y: Style.space(2)
              radius: Style.cornerRadius
              color: dragArea.drag.active
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                : (root.cursor === wrap.index || dragArea.containsMouse)
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

              Behavior on color { ColorAnimation { duration: 80 } }

              Text {
                id: grip
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.iconGrip
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.8)
              }

              Text {
                anchors.left: grip.right
                anchors.leftMargin: Style.space(8)
                anchors.right: eye.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: wrap.model.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.foreground
                opacity: wrap.model.hid ? 0.4 : 1
              }

              // Eye = shown, slashed eye = parked off the bar. Clicked through the
              // drag area's hit test below (a sibling MouseArea would sit under it).
              Text {
                id: eye
                anchors.right: pos.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: wrap.model.hid ? root.iconEyeSlash : root.iconEye
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: wrap.model.hid ? Qt.darker(root.foreground, 1.6) : root.foreground
                opacity: wrap.model.hid ? 0.8 : 0.55
              }

              Text {
                id: pos
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: (wrap.index + 1)
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.7)
                opacity: wrap.model.hid ? 0.4 : 1
              }
            }

            MouseArea {
              id: dragArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
              drag.target: card
              drag.axis: Drag.YAxis
              onContainsMouseChanged: if (containsMouse) root.cursor = wrap.index
              onClicked: function(mouse) {
                var p = dragArea.mapToItem(eye, mouse.x, mouse.y)
                if (p.x > -Style.space(6) && p.x < eye.width + Style.space(6)
                    && p.y > -Style.space(8) && p.y < eye.height + Style.space(8))
                  root.toggleHidden(wrap.index)
              }
              onPositionChanged: {
                if (!drag.active) return
                var centerY = card.mapToItem(list.contentItem, 0, card.height / 2).y
                var to = Math.max(0, Math.min(lm.count - 1,
                                              Math.floor(centerY / list.slotHeight)))
                if (to !== wrap.index) root.moveItem(wrap.index, to)
              }
              onReleased: card.y = Style.space(2)
              onCanceled: card.y = Style.space(2)
            }
          }
        }

        Text {
          width: parent.width
          text: "drag or j/k + J/K  ·  eye / x hides  ·  Enter applies  ·  Esc cancels"
          textFormat: Text.PlainText
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.7)
        }
      }
    }
  }
}
