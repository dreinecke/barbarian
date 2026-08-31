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
// How it works: the panel reads shell.json's right section into a list; rows are DRAGGED
// with the mouse or nudged with keys, which only reorders the list; the file is written
// ONCE, when the panel closes (Enter, click-away) — Escape throws the changes away. The
// write goes through bin/bar-arrange-apply, which moves whole entries so per-widget
// settings (the clock's formats) travel untouched, and the bar hot-reloads on the write.
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
      var layout = JSON.parse(text).bar.layout.right
      for (var i = 0; i < layout.length; i++) {
        var wid = String(layout[i].id || "")
        if (wid === "" || wid === selfId) continue
        lm.append({ wid: wid, label: prettyName(wid) })
      }
    } catch (e) {
      loadError = "Could not read the bar layout file."
    }
    cursor = 0
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
    for (var i = 0; i < lm.count; i++) argv.push(lm.get(i).wid)
    applyProc.command = argv
    applyProc.running = true
  }

  function acceptAndClose() { close() }
  function cancelAndClose() { cancelled = true; close() }

  onOpenedChanged: {
    if (opened) {
      dirty = false
      cancelled = false
      readProc.command = ["sh", "-c", "cat \"$HOME/.config/omarchy/shell.json\""]
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
                anchors.right: pos.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: wrap.model.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.foreground
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
          text: "drag rows, or j/k + J/K  ·  Enter applies  ·  Esc cancels"
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
