import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Arrange: reorder, hide and re-lane the bar's widgets from a panel, because dragging
// the real bar icons in place would mean reaching into the shell's private layout code
// (not ours, and overwritten on every Omarchy update). Dave, 2026-08-31, offered this as
// the sturdy version of "hold hyper and drag the bar" — "The word :)".
//
// TWO COLUMNS since 2026-09-01 (Dave: "Left column for left side and right column for
// right side"): the left column is the bar's far-left lane, the right column its right
// lane. Rows are DRAGGED — within a column to reorder, ACROSS to change lanes (the move
// lands when the row is dropped) — or nudged with keys: j/k walk, h/l switch column,
// J/K carry the row, H/L throw it to the other column. The eye button (or `x`) hides a
// row (Dave, 2026-09-01: Bluetooth is "noise/clutter 99% of the time but occasionally I
// want" it back). Files are written ONCE, when the panel closes (Enter, click-away) —
// Escape throws the changes away. The write goes through bin/bar-arrange-apply, which
// moves whole entries so per-widget settings (the clock's formats) travel untouched — a
// hidden entry is parked in the sidecar with its settings, lane and position, never
// deleted — and the bar hot-reloads.
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

  readonly property string iconGrip: ""
  readonly property string iconCheck: ""
  readonly property string iconX: ""
  readonly property string iconEye: ""
  readonly property string iconEyeSlash: ""

  property string curLane: "R"
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
      "tinkerbell.tray": "System tray",
      "limehawk.vpn": "VPN",
      "pestov.apple-music": "Apple Music",
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

  ListModel { id: lmL }
  ListModel { id: lmR }

  function modelFor(lane) { return lane === "L" ? lmL : lmR }

  function fillLane(model, layout, parked) {
    model.clear()
    var rows = []
    for (var i = 0; i < layout.length; i++) {
      var wid = String(layout[i].id || "")
      if (wid === "" || wid === selfId) continue
      rows.push({ wid: wid, label: prettyName(wid), hid: false })
    }
    // Hidden entries come back at (or near) the spot they were hidden from.
    parked.sort(function(a, b) { return (a.index || 0) - (b.index || 0) })
    for (var p = 0; p < parked.length; p++) {
      var pw = String((parked[p].entry || {}).id || "")
      if (pw === "" || pw === selfId) continue
      var at = Math.min(Math.max(0, parked[p].index || 0), rows.length)
      rows.splice(at, 0, { wid: pw, label: prettyName(pw), hid: true })
    }
    for (var r = 0; r < rows.length; r++) model.append(rows[r])
  }

  function loadRows(text) {
    loadError = ""
    try {
      // Two files ride one cat (see readProc): shell.json, a marker, bar-hidden.json.
      var parts = text.split("---BARHIDDEN---")
      var layout = JSON.parse(parts[0]).bar.layout
      var parked = {}
      try { parked = JSON.parse(parts[1] || "{}") } catch (e2) {}
      fillLane(lmL, layout.left || [], parked.left || [])
      fillLane(lmR, layout.right || [], parked.right || [])
    } catch (e) {
      loadError = "Could not read the bar layout file."
    }
    curLane = lmR.count > 0 ? "R" : "L"
    cursor = 0
  }

  function toggleHidden(lane, i) {
    var m = modelFor(lane)
    if (i < 0 || i >= m.count) return
    m.setProperty(i, "hid", !m.get(i).hid)
    dirty = true
  }

  function moveItem(lane, from, to) {
    var m = modelFor(lane)
    if (from === to || from < 0 || to < 0 || from >= m.count || to >= m.count) return
    m.move(from, to, 1)
    if (curLane === lane) cursor = to
    dirty = true
  }

  // A row changes lanes whole: removed from one column, inserted into the other at the
  // drop position. The cursor follows it.
  function moveAcross(fromLane, index, toLane, at) {
    if (fromLane === toLane) return
    var m1 = modelFor(fromLane), m2 = modelFor(toLane)
    if (index < 0 || index >= m1.count) return
    var r = m1.get(index)
    var row = { wid: r.wid, label: r.label, hid: r.hid }
    m1.remove(index)
    at = Math.min(Math.max(0, at), m2.count)
    m2.insert(at, row)
    curLane = toLane
    cursor = at
    dirty = true
  }

  function moveCursor(delta) {
    var m = modelFor(curLane)
    if (m.count === 0) return
    cursor = Math.max(0, Math.min(m.count - 1, cursor + delta))
  }

  function switchLane(dir) {
    var to = dir < 0 ? "L" : "R"
    if (to === curLane || modelFor(to).count === 0) return
    curLane = to
    cursor = Math.max(0, Math.min(modelFor(to).count - 1, cursor))
  }

  function apply() {
    if (applyProc.running) return
    var argv = [applyScript]
    var i
    for (i = 0; i < lmL.count; i++)
      argv.push("L:" + lmL.get(i).wid + (lmL.get(i).hid ? ":hidden" : ""))
    for (i = 0; i < lmR.count; i++)
      argv.push("R:" + lmR.get(i).wid + (lmR.get(i).hid ? ":hidden" : ""))
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

  // The row delegate both columns share. Drag within a column reorders live; drag past
  // the column gap and release, and the row lands in the other column at the drop spot.
  component LaneList: ListView {
    id: list

    // "L" or "R" — which bar lane this column edits.
    property string lane: "R"
    // The other column, for cross-drop coordinate math.
    property ListView other: null

    readonly property int slotHeight: Style.space(34)
    width: parent.width
    height: Math.max(1, count) * slotHeight   // ≥ one slot, so an empty lane is a drop target
    clip: false                               // a card dragged across the gap must stay visible
    interactive: false
    spacing: 0
    model: lane === "L" ? lmL : lmR

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
          : (root.curLane === list.lane && root.cursor === wrap.index) || dragArea.containsMouse
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

        // Eye = shown, slashed eye = parked off the bar. Clicked through the drag
        // area's hit test below (a sibling MouseArea would sit under it).
        Text {
          id: eye
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: wrap.model.hid ? root.iconEyeSlash : root.iconEye
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: wrap.model.hid ? Qt.darker(root.foreground, 1.6) : root.foreground
          opacity: wrap.model.hid ? 0.8 : 0.55
        }
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: card
        drag.axis: Drag.XAndYAxis

        onContainsMouseChanged: if (containsMouse) { root.curLane = list.lane; root.cursor = wrap.index }
        onClicked: function(mouse) {
          var p = dragArea.mapToItem(eye, mouse.x, mouse.y)
          if (p.x > -Style.space(6) && p.x < eye.width + Style.space(6)
              && p.y > -Style.space(8) && p.y < eye.height + Style.space(8))
            root.toggleHidden(list.lane, wrap.index)
        }
        onPositionChanged: {
          if (!drag.active || !list.other) return
          var c = card.mapToItem(list, card.width / 2, card.height / 2)
          if (c.x >= 0 && c.x <= list.width) {
            // Still over the home column: live-reorder as before.
            var centerY = card.mapToItem(list.contentItem, 0, card.height / 2).y
            var to = Math.max(0, Math.min(list.count - 1,
                                          Math.floor(centerY / list.slotHeight)))
            if (to !== wrap.index) root.moveItem(list.lane, wrap.index, to)
          }
        }
        onReleased: {
          // Dropped over the other column? The row changes lanes at the drop position.
          if (list.other) {
            var o = card.mapToItem(list.other, card.width / 2, card.height / 2)
            if (o.x >= -Style.space(6) && o.x <= list.other.width + Style.space(6)) {
              var at = Math.max(0, Math.min(list.other.count,
                                            Math.round(o.y / list.slotHeight)))
              root.moveAcross(list.lane, wrap.index, list.other.lane, at)
            }
          }
          card.x = 0; card.y = Style.space(2)
        }
        onCanceled: { card.x = 0; card.y = Style.space(2) }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Escape CANCELS (nothing written); Enter and click-away APPLY.
      onCloseRequested: root.cancelAndClose()
      onActivateRequested: root.acceptAndClose()
      // x (PanelKeyCatcher's delete key) hides/shows the selected row.
      onDeleteRequested: root.toggleHidden(root.curLane, root.cursor)
      // j/k (dy) walk a column, h/l (dx) hop between the two.
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        if (dx !== 0) root.switchLane(dx)
      }
      // J/K carry the selected row up/down; H/L throw it to the other column.
      onTextKey: function(t) {
        if (t === "J") root.moveItem(root.curLane, root.cursor, root.cursor + 1)
        else if (t === "K") root.moveItem(root.curLane, root.cursor, root.cursor - 1)
        else if (t === "H") root.moveAcross(root.curLane, root.cursor, "L", root.cursor)
        else if (t === "L") root.moveAcross(root.curLane, root.cursor, "R", root.cursor)
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
            text: "Bar widgets"
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
              tooltipText: "Apply"
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

        Row {
          id: laneRow
          width: parent.width
          spacing: Style.space(14)

          readonly property real colWidth: (width - spacing) / 2

          Column {
            width: laneRow.colWidth
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "LEFT"
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Qt.darker(root.foreground, 1.6)
            }

            LaneList {
              id: lviewL
              lane: "L"
              other: lviewR
            }
          }

          Column {
            width: laneRow.colWidth
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "RIGHT"
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              color: Qt.darker(root.foreground, 1.6)
            }

            LaneList {
              id: lviewR
              lane: "R"
              other: lviewL
            }
          }
        }

        Text {
          width: parent.width
          text: "drag rows, across too  ·  j/k h/l + J/K H/L  ·  eye / x hides  ·  Enter applies  ·  Esc cancels"
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
