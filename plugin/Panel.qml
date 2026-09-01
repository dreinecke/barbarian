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
  readonly property string pickScript:
    Qt.resolvedUrl("bin/ws-bg-pick").toString().replace(/^file:\/\//, "")
  // This widget must never list (or reorder away) itself.
  readonly property string selfId: "tinkerbell.arrange"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string iconHero: "󰞇"
  readonly property string iconGrip: ""
  readonly property string iconCheck: ""
  readonly property string iconX: ""
  readonly property string iconEye: ""
  readonly property string iconEyeSlash: ""
  readonly property string iconPencil: ""
  readonly property string iconSave: ""
  readonly property string iconImage: "󰥶"
  readonly property string iconRestore: ""

  property string curLane: "R"
  property int cursor: 0
  property bool dirty: false
  property bool cancelled: false
  property string loadError: ""
  // The middle (workspaces) column: which row is being renamed inline (-1 = none), and
  // whether renaming exists on this machine at all (workspace-edit is SER8-only — on the
  // MacBook names come from the sync, so the pencil is not offered there).
  property int wsEditing: -1
  property bool canRename: false
  // Where the workspaces strip sits on the bar — Barbarian's MODE (Dave, 2026-09-01):
  // "1" strip far left, icons centre + right · "2" icons left, strip centre (stock) ·
  // "3" icons in all three sections, the strip parked off the bar. Derived from
  // shell.json on every open and applied, like everything else, on close.
  property string mode: "2"
  // The strip's widget id as found in the layout (tinkerbell.workspaces here,
  // omarchy.workspaces stock) — the apply script moves it whole between sections.
  property string wsWidgetId: ""
  // The background picker (Dave, 2026-09-01): which desk's thumbnail strip is open
  // (-1 = none), and the current theme's background images to offer.
  property int bgPicking: -1
  property var bgThemeList: []
  // Solid-colour choices for the picker: black plus the current theme's palette.
  property var bgSolids: []

  // The hero's subtitle: one bar pun per opening, cycling through the lot. The pool
  // is Dave-curated (2026-09-01, a 58-strong long-list cut to these survivors).
  // Starts somewhere random so a shell restart does not reset the tour to the top.
  readonly property var mottos: [
    "No holds barred", "Barbarians at the gate", "Barred from entering",
    "Hanna-Barbera", "Bar-ram-ewe", "Bar bar black sheep", "Obarma care",
    "Raising the bar", "Bar none", "Behind bars", "The bar exam",
    "Salad bar", "Space bar", "Crowbar", "Handlebar moustache",
    "Chocolate bar", "Bar humbug", "Granola bar", "Foo-bar",
    "Nothing bar the truth", "Two icons walk into a bar",
    "Bar the shouting", "Barred for life", "Barring any objections",
    "Barring a miracle", "A galaxy bar, bar away", "So bar, so good",
    "As bar as the eye can see", "Bar from perfect",
    "The simple Bar Necessities", "Bar-barian Rhapsody",
    "Bar-anormal activity", "One Bar to Rule Them All",
    "Friends, Romans, countrymen, lend me your bars",
    "A rolling bar gathers no moss",
    "I'm going to make him a bar he can't refuse", "Bar-adise"
  ]
  property int motto: Math.floor(Math.random() * 9973)

  // Nothing on the bar: the panel is the whole widget.
  implicitWidth: 0
  implicitHeight: 0

  // Friendly names for the ids Dave actually has; anything unknown falls back to its id's
  // last segment so a future widget still gets a readable row.
  function prettyName(wid) {
    var known = {
      "omarchy.tray": "System Tray",
      "omarchy.agents": "Agents",
      "omarchy.bluetooth": "Bluetooth",
      "omarchy.network": "Network",
      "omarchy.audio": "Audio",
      "omarchy.monitor": "System Monitor",
      "tinkerbell.mail": "Mail",
      "tinkerbell.messages": "Messages",
      "tinkerbell.tray": "System Tray",
      "limehawk.vpn": "VPN",
      "pestov.apple-music": "Apple Music",
      "jankeesvw.downloads": "Downloads",
      "jankeesvw.time-machine": "Time Machine",
      "jankeesvw.notification-center": "Notifications",
      "omarchy.indicators": "Indicators",
      "omarchy.clock": "Clock",
      "omarchy.keyboard-layout": "Keyboard Layout",
      "omarchy.system-update": "System Update",
      "omarchy.power": "Power",
      "omarchy.weather": "Weather",
      "omarchy.workspaces": "Workspaces",
      "omarchy.spacer": "Spacer"
    }
    if (known[wid] !== undefined) return known[wid]
    // Unknown ids fall back to their id's last segment, Title Cased like the rest —
    // the mixed casing bugged Dave (2026-09-01).
    var tail = String(wid).split(".").pop().replace(/-/g, " ")
    return tail.replace(/\b[a-z]/g, function(c) { return c.toUpperCase() })
  }

  // The glyph each widget wears on the bar (Dave, 2026-09-01: "🎧 Audio" not "Audio"),
  // same icon font the bar itself uses. Unknown ids get no glyph, and the fixed-width
  // icon slot keeps the names aligned either way.
  function iconFor(wid) {
    var icons = {
      "omarchy.tray": "",
      "tinkerbell.tray": "",
      "tinkerbell.mail": "",
      "tinkerbell.messages": "",
      "omarchy.agents": "󱚣",
      "limehawk.vpn": "",
      "omarchy.network": "󰈀",
      "omarchy.audio": "",
      "omarchy.monitor": "",
      "omarchy.bluetooth": "",
      "jankeesvw.time-machine": "",
      "jankeesvw.notification-center": "",
      "jankeesvw.downloads": "",
      "omarchy.indicators": "",
      "omarchy.keyboard-layout": "",
      "omarchy.power": "",
      "pestov.apple-music": "",
      "omarchy.system-update": "",
      "omarchy.clock": "",
      "omarchy.weather": "",
      "omarchy.workspaces": ""
    }
    return icons[wid] || ""
  }

  // Whether a widget is ACTUALLY drawing anything on the bar right now — independent of
  // our show/hide setting. Time Machine hides itself while backups are healthy, the
  // indicators shrink to nothing when no state is active, and Dave found the two axes
  // confusing when they wore one style (2026-09-01): so the label's STRIKETHROUGH is our
  // setting (crossed = parked off the bar), and its BRIGHTNESS is the live fact (faded =
  // drawing nothing at this moment).
  function visibleNow(wid) {
    if (!bar || typeof bar.moduleWidgets !== "function") return true
    var items = bar.moduleWidgets(wid)
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it.visible === false) continue
      var w = (it.implicitWidth !== undefined && it.implicitWidth !== null)
        ? it.implicitWidth : (it.width || 0)
      if (w > 1) return true
    }
    return false
  }

  ListModel { id: lmL }
  ListModel { id: lmC }
  ListModel { id: lmR }
  ListModel { id: lmW }   // the desks

  function modelFor(lane) { return lane === "L" ? lmL : lane === "C" ? lmC : lmR }

  // The icon lanes visible in the current mode, left to right on screen.
  function laneOrder() {
    return mode === "1" ? ["C", "R"] : mode === "2" ? ["L", "R"] : ["L", "C", "R"]
  }

  // Switching mode moves the strip; the icon lane that loses its column empties into
  // its neighbour so no icon is stranded in an invisible lane.
  function setMode(m) {
    if (m === mode) return
    if (m === "1") drainLane(lmL, lmC)
    else if (m === "2") drainLane(lmC, lmL)
    mode = m
    var lanes = laneOrder()
    if (lanes.indexOf(curLane) < 0) { curLane = lanes[0]; cursor = 0 }
    dirty = true
  }
  function drainLane(from, into) {
    var at = 0
    while (from.count > 0) {
      var r = from.get(0)
      into.insert(at++, { wid: r.wid, label: r.label, glyph: r.glyph, hid: r.hid, lit: r.lit })
      from.remove(0)
    }
  }

  // Desks come from Hyprland itself (works on both machines); recordings from the
  // HYPER+S snapshot directory. Reordering desks is deliberately NOT offered: a desk's
  // NUMBER is load-bearing in four places that do not read each other (AGENTS.md names
  // them), so renumbering is a hands-on job, never a drag.
  function fillWorkspaces(wsJson, activeJson, snapText, pins) {
    pins = pins || {}
    lmW.clear()
    var active = -1
    try { active = JSON.parse(activeJson).id } catch (e) {}
    var snaps = {}
    var lines = String(snapText || "").split("\n")
    for (var s = 0; s < lines.length; s++) {
      var m = lines[s].match(/^ws(\d+)\.json$/)
      if (m) snaps[parseInt(m[1], 10)] = true
    }
    var list = []
    try { list = JSON.parse(wsJson) } catch (e2) { return }
    list.sort(function(a, b) { return a.id - b.id })
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (w.id < 1) continue   // scratchpads / specials
      var nm = String(w.name || "")
      if (nm === "" || nm === String(w.id)) nm = "Desk " + w.id
      lmW.append({ num: w.id, name: nm, focused: w.id === active, hasSnap: snaps[w.id] === true,
                   bgPin: String(pins[w.id] || "") })
    }
  }

  function wsFocus(n) {
    wsActProc.command = ["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "' + n + '" })']
    wsActProc.running = true
  }
  function wsSave(n) {
    wsActProc.command = ["sh", "-c",
      '"$HOME/.config/omarchy/workspace-layout/ws-layout" snapshot ' + n]
    wsActProc.running = true
    var m = rowForWs(n); if (m >= 0) lmW.setProperty(m, "hasSnap", true)
  }
  function wsRestore(n) {
    wsActProc.command = ["sh", "-c",
      '"$HOME/.config/omarchy/workspace-layout/ws-layout" restore ' + n]
    wsActProc.running = true
  }
  function wsRename(n, name) {
    name = String(name || "").trim()
    if (name === "") return
    wsActProc.command = ["sh", "-c",
      '"$HOME/.local/bin/workspace-edit" set ' + n + " --name " + JSON.stringify(name)]
    wsActProc.running = true
    var m = rowForWs(n); if (m >= 0) lmW.setProperty(m, "name", name)
  }
  // Pin desk n's wallpaper (or "default" to unpin). ws-bg-pick moves the pin file and
  // repaints immediately if n is the desk on screen; the row updates optimistically.
  function bgPick(n, path) {
    wsActProc.command = ["sh", "-c",
      '"' + pickScript + '" ' + n + " " + JSON.stringify(path)]
    wsActProc.running = true
    var m = rowForWs(n)
    if (m >= 0) lmW.setProperty(m, "bgPin", path === "default" ? "" : path)
    bgPicking = -1
  }

  // The + chip: open this theme's user background folder (stock `omarchy theme bg
  // install`) — drop images in, reopen the picker, they are in the strip.
  function bgAddImages() {
    wsActProc.command = ["sh", "-c", "setsid -f omarchy-theme-bg-install >/dev/null 2>&1"]
    wsActProc.running = true
  }

  function rowForWs(n) {
    for (var i = 0; i < lmW.count; i++) if (lmW.get(i).num === n) return i
    return -1
  }

  function fillLane(model, layout, parked) {
    model.clear()
    var rows = []
    for (var i = 0; i < layout.length; i++) {
      var wid = String(layout[i].id || "")
      if (wid === "" || wid === selfId || wid === wsWidgetId) continue
      rows.push({ wid: wid, label: prettyName(wid), glyph: iconFor(wid), hid: false,
                  lit: visibleNow(wid) })
    }
    // Hidden entries come back at (or near) the spot they were hidden from.
    parked.sort(function(a, b) { return (a.index || 0) - (b.index || 0) })
    for (var p = 0; p < parked.length; p++) {
      var pw = String((parked[p].entry || {}).id || "")
      if (pw === "" || pw === selfId || pw === wsWidgetId) continue
      var at = Math.min(Math.max(0, parked[p].index || 0), rows.length)
      rows.splice(at, 0, { wid: pw, label: prettyName(pw), glyph: iconFor(pw), hid: true,
                           lit: false })
    }
    for (var r = 0; r < rows.length; r++) model.append(rows[r])
  }

  function loadRows(text) {
    loadError = ""
    try {
      // Two files ride one cat (see readProc): shell.json, a marker, bar-hidden.json.
      var parts = text.split("---BARHIDDEN---")
      var layout = JSON.parse(parts[0]).bar.layout
      var rest = String(parts[1] || "").split("---WS---")
      var parked = {}
      try { parked = JSON.parse(rest[0] || "{}") } catch (e2) {}
      var secL = layout.left || [], secC = layout.center || [], secR = layout.right || []
      var pkL = parked.left || [], pkC = parked.center || [], pkR = parked.right || []
      function findWs(list) {
        for (var fi = 0; fi < list.length; fi++)
          if (/\.workspaces$/.test(String(list[fi].id || ""))) return String(list[fi].id)
        return ""
      }
      function ents(rows) {
        var o = []
        for (var ei = 0; ei < rows.length; ei++) o.push(rows[ei].entry || {})
        return o
      }
      var inL = findWs(secL), inC = findWs(secC), inR = findWs(secR)
      wsWidgetId = inL || inC || inR
        || findWs(ents(pkL).concat(ents(pkC)).concat(ents(pkR)))
      // A strip in the right section has no mode of its own — treated as centre, and
      // the next apply moves it there.
      mode = inL ? "1" : (inC || inR) ? "2" : "3"
      fillLane(lmL, secL, pkL)
      fillLane(lmC, secC, pkC)
      fillLane(lmR, secR, pkR)
      var tail = String(rest[1] || "").split("---ACTIVE---")
      var tail2 = String(tail[1] || "").split("---SNAPS---")
      var tail3 = String(tail2[1] || "").split("---CANRENAME---")
      var tail4 = String(tail3[1] || "").split("---BGS---")
      var tail4b = String(tail4[1] || "").split("---COLORS---")
      var tail5 = String(tail4b[1] || "").split("---PINS---")
      canRename = String(tail4[0] || "").trim() !== ""
      var bgs = [], bl = String(tail4b[0] || "").split("\n")
      for (var bi = 0; bi < bl.length; bi++)
        if (/\.(jpg|jpeg|png)$/i.test(bl[bi].trim())) bgs.push(bl[bi].trim())
      bgThemeList = bgs
      // Black first, then the theme's own colours, deduped (last-horizon's blue IS its
      // accent) — these become the solid swatches.
      var sol = [{ name: "black", hex: "#000000" }]
      var seen = { "#000000": true }
      var ckeys = ["background", "accent", "muted", "red", "yellow", "green", "cyan", "blue", "magenta"]
      var cl = String(tail4b[1].split("---PINS---")[0] || "").split("\n")
      for (var ci = 0; ci < cl.length; ci++) {
        var cm = cl[ci].match(/^\s*([A-Za-z_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (!cm || ckeys.indexOf(cm[1]) < 0) continue
        var hx = cm[2].toLowerCase()
        if (seen[hx]) continue
        seen[hx] = true
        sol.push({ name: cm[1], hex: hx })
      }
      bgSolids = sol
      var pins = {}
      var pl = String(tail5[1] || "").split("\n")
      for (var pi = 0; pi < pl.length; pi++) {
        var pm = pl[pi].match(/\/ws(\d+)\.[A-Za-z]+\|(.+)$/)
        if (pm) pins[parseInt(pm[1], 10)] = pm[2].trim()
      }
      fillWorkspaces(tail[0] || "[]", tail2[0] || "{}", tail3[0] || "", pins)
    } catch (e) {
      loadError = "Could not read the bar layout file."
    }
    wsEditing = -1
    bgPicking = -1
    var lanes = laneOrder()
    curLane = lanes[0]
    for (var li = 0; li < lanes.length; li++)
      if (modelFor(lanes[li]).count > 0) { curLane = lanes[li]; break }
    cursor = 0
  }

  function toggleHidden(lane, i) {
    var m = modelFor(lane)
    if (i < 0 || i >= m.count) return
    var nowHid = !m.get(i).hid
    m.setProperty(i, "hid", nowHid)
    // Optimistic: an un-parked widget lights up (it only actually draws after apply).
    m.setProperty(i, "lit", !nowHid)
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
    var row = { wid: r.wid, label: r.label, glyph: r.glyph, hid: r.hid, lit: r.lit }
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
    var lanes = laneOrder()
    var i = lanes.indexOf(curLane)
    if (i < 0) i = 0
    var j = i + (dir < 0 ? -1 : 1)
    while (j >= 0 && j < lanes.length && modelFor(lanes[j]).count === 0)
      j += (dir < 0 ? -1 : 1)
    if (j < 0 || j >= lanes.length) return
    curLane = lanes[j]
    cursor = Math.max(0, Math.min(modelFor(curLane).count - 1, cursor))
  }

  // H/L throw the selected row into the neighbouring icon lane.
  function throwAcross(dir) {
    var lanes = laneOrder()
    var i = lanes.indexOf(curLane)
    var j = i + dir
    if (i < 0 || j < 0 || j >= lanes.length) return
    moveAcross(curLane, cursor, lanes[j], cursor)
  }

  function apply() {
    if (applyProc.running) return
    var argv = [applyScript]
    var lanes = laneOrder(), i
    for (var li = 0; li < lanes.length; li++) {
      var m = modelFor(lanes[li])
      for (i = 0; i < m.count; i++)
        argv.push(lanes[li] + ":" + m.get(i).wid + (m.get(i).hid ? ":hidden" : ""))
    }
    if (wsWidgetId !== "")
      argv.push("WS:" + wsWidgetId + ":"
        + (mode === "1" ? "left" : mode === "2" ? "center" : "hidden"))
    applyProc.command = argv
    applyProc.running = true
  }

  function acceptAndClose() { close() }
  function cancelAndClose() { cancelled = true; close() }

  onOpenedChanged: {
    if (opened) {
      dirty = false
      cancelled = false
      motto++
      readProc.command = ["sh", "-c",
        "cat \"$HOME/.config/omarchy/shell.json\"; echo ---BARHIDDEN---; cat \"$HOME/.config/omarchy/bar-hidden.json\" 2>/dev/null || echo '{}'; " +
        "echo ---WS---; hyprctl workspaces -j 2>/dev/null; echo ---ACTIVE---; hyprctl activeworkspace -j 2>/dev/null; " +
        "echo ---SNAPS---; ls \"$HOME/.config/omarchy/workspace-layout/snapshots\" 2>/dev/null; " +
        "echo ---CANRENAME---; command -v \"$HOME/.local/bin/workspace-edit\" 2>/dev/null || true; " +
        "echo ---BGS---; tn=\"$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null)\"; d=\"$(readlink -f \"$HOME/.local/state/omarchy/current/theme\")/backgrounds\"; find -L \"$HOME/.config/omarchy/backgrounds/$tn\" \"$d\" -maxdepth 1 -type f 2>/dev/null | sort; " +
        "echo ---COLORS---; cat \"$HOME/.local/state/omarchy/current/theme/colors.toml\" 2>/dev/null; " +
        "echo ---PINS---; for f in \"$HOME/.config/omarchy/workspace-backgrounds\"/ws*.*; do [ -e \"$f\" ] && echo \"$f|$(readlink -f \"$f\")\"; done; true"]
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

  // One desk action at a time (focus / save / restore / rename) — each tool it calls
  // does its own toasting, so nothing is echoed here.
  Process {
    id: wsActProc
  }

  // The row delegate both columns share. Drag within a column reorders live; drag past
  // the column gap and release, and the row lands in the other column at the drop spot.
  component LaneList: ListView {
    id: list

    // "L", "C" or "R" — which bar section this column edits.
    property string lane: "R"
    // The other icon columns, for cross-drop coordinate math.
    property var others: []

    readonly property int slotHeight: Style.space(34)
    width: parent.width
    // One empty slot beyond the last row, always — so there is visibly room to drop
    // something at the end of either column (Dave, 2026-09-01), and an empty lane is
    // still a drop target.
    height: (count + 1) * slotHeight
    clip: false                               // a card dragged across the gap must stay visible
    interactive: false
    spacing: 0
    model: lane === "L" ? lmL : lane === "C" ? lmC : lmR

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

        // Grip lives at the row's far END (Dave, 2026-09-01) so the widget's own glyph
        // leads the row instead of fighting the hamburger visually.
        Text {
          id: grip
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.iconGrip
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.8)
        }

        // An Item centring a Text, not AlignHCenter: the icons' advance widths vary
        // (the Bluetooth rune is half the robot's width), and text alignment left the
        // narrow ones visibly off-centre in the slot (Dave, 2026-09-01). centerIn
        // centres the glyph's actual box, whatever its width.
        Item {
          id: glyphSlot
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(22)
          height: glyphText.implicitHeight

          Text {
            id: glyphText
            anchors.centerIn: parent
            text: wrap.model.glyph
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            // Dave's second mock-editor pass (2026-09-01): foreground at 55%, dim 25%;
            // headings and helper wear muted, the rules accent at 18%.
            color: root.foreground
            opacity: wrap.model.lit ? 0.55 : 0.25
          }
        }

        Text {
          anchors.left: glyphSlot.right
          anchors.leftMargin: Style.space(8)
          anchors.right: eye.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: wrap.model.label
          textFormat: Text.PlainText
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.strikeout: wrap.model.hid        // crossed = our setting says hide
          color: root.foreground
          opacity: wrap.model.lit ? 1 : 0.25    // faded = drawing nothing right now
        }

        // Eye = shown, slashed eye = parked off the bar. Clicked through the drag
        // area's hit test below (a sibling MouseArea would sit under it).
        Text {
          id: eye
          anchors.right: grip.left
          anchors.rightMargin: Style.space(10)
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
          if (!drag.active) return
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
          // Dropped over another visible icon column? The row changes lanes there.
          for (var oi = 0; oi < list.others.length; oi++) {
            var ol = list.others[oi]
            if (!ol || !ol.visible) continue
            var o = card.mapToItem(ol, card.width / 2, card.height / 2)
            if (o.x >= -Style.space(6) && o.x <= ol.width + Style.space(6)) {
              var at = Math.max(0, Math.min(ol.count, Math.round(o.y / list.slotHeight)))
              root.moveAcross(list.lane, wrap.index, ol.lane, at)
              break
            }
          }
          card.x = 0; card.y = Style.space(2)
        }
        onCanceled: { card.x = 0; card.y = Style.space(2) }
      }
    }
  }

  // The desks column body — go, rename (SER8 only, the sync owns the MacBook's names),
  // save (HYPER+S) and restore (HYPER+R) per desk. Reusable in whichever slot the mode
  // puts it. No dragging here: a desk's NUMBER is load-bearing in four places
  // (see fillWorkspaces).
  component DeskList: Column {
    id: dlist
    spacing: 0

    Repeater {
      model: lmW

            delegate: Item {
        id: wrow
        required property var model
        required property int index

        width: dlist.width
        height: Style.space(34)
          + (root.bgPicking === wrow.model.num ? bgFlow.implicitHeight + Style.space(6) : 0)

        Rectangle {
          id: wcard
          width: wrow.width
          height: wrow.height - Style.space(4)
          y: Style.space(2)
          radius: Style.cornerRadius
          color: wrow.model.focused
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            : nameArea.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

          Text {
            id: wnum
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: wrow.model.num
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Qt.darker(root.foreground, 1.6)
          }

          Text {
            id: wname
            visible: root.wsEditing !== wrow.index
            anchors.left: wnum.right
            anchors.leftMargin: Style.space(8)
            anchors.right: wimg.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: wrow.model.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
          }

          TextField {
            id: wedit
            visible: root.wsEditing === wrow.index
            anchors.left: wnum.right
            anchors.leftMargin: Style.space(4)
            anchors.right: wimg.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
            onVisibleChanged: if (visible) { text = wrow.model.name; forceActiveFocus(); selectAll() }
            onAccepted: { root.wsRename(wrow.model.num, text); root.wsEditing = -1 }
            Keys.onEscapePressed: root.wsEditing = -1
          }

          MouseArea {
            id: nameArea
            anchors.left: parent.left
            anchors.right: wimg.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            hoverEnabled: true
            enabled: root.wsEditing !== wrow.index
            onClicked: root.wsFocus(wrow.model.num)
          }

          PanelActionButton {
            id: wimg
            anchors.right: wpencil.left
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.iconImage
            tooltipText: "Background"
            // Accent when this desk has a pinned image of its own.
            foreground: wrow.model.bgPin !== "" ? root.accent : Qt.darker(root.foreground, 1.8)
            hoverColor: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.bgPicking = root.bgPicking === wrow.model.num ? -1 : wrow.model.num
          }

          PanelActionButton {
            id: wpencil
            visible: root.canRename
            anchors.right: wsave.left
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.iconPencil
            tooltipText: "Rename"
            foreground: Qt.darker(root.foreground, 1.8)
            hoverColor: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.wsEditing = root.wsEditing === wrow.index ? -1 : wrow.index
          }

          PanelActionButton {
            id: wsave
            anchors.right: wrestore.left
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.iconSave
            tooltipText: "Save layout (HYPER+S)"
            foreground: Qt.darker(root.foreground, 1.8)
            hoverColor: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.wsSave(wrow.model.num)
          }

          PanelActionButton {
            id: wrestore
            anchors.right: parent.right
            anchors.rightMargin: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.iconRestore
            tooltipText: wrow.model.hasSnap ? "Restore layout (HYPER+R)" : "No recording yet"
            foreground: Qt.darker(root.foreground, 1.8)
            hoverColor: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            opacity: wrow.model.hasSnap ? 1 : 0.3
            onClicked: if (wrow.model.hasSnap) root.wsRestore(wrow.model.num)
          }
        }

        // The picker: Auto (no pin — the blanket/theme chain decides, see
        // per-workspace-wallpaper.sh) plus the current theme's backgrounds.
        Flow {
          id: bgFlow
          visible: root.bgPicking === wrow.model.num
          anchors.top: wcard.bottom
          anchors.topMargin: Style.space(2)
          width: wrow.width
          spacing: Style.space(4)

          Rectangle {
            width: Style.space(56)
            height: Style.space(32)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            border.width: wrow.model.bgPin === "" ? 2 : 1
            border.color: wrow.model.bgPin === "" ? root.accent
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

            Text {
              anchors.centerIn: parent
              text: "Auto"
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: root.muted
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.bgPick(wrow.model.num, "default")
            }
          }

          // Solid colours: black, then this theme's palette (ws-bg-pick turns the hex
          // into a flat PNG, since the shell's background only takes image paths).
          Repeater {
            model: root.bgSolids

            delegate: Rectangle {
              required property var modelData
              readonly property bool current:
                wrow.model.bgPin.indexOf("/solids/" + modelData.hex.slice(1) + ".png") >= 0
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.cornerRadius
              color: modelData.hex
              border.width: current ? 2 : 1
              border.color: current ? root.accent
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

              MouseArea {
                anchors.fill: parent
                onClicked: root.bgPick(wrow.model.num, "solid:" + modelData.hex)
              }
            }
          }

          Repeater {
            model: root.bgThemeList

            delegate: Rectangle {
              required property var modelData
              width: Style.space(56)
              height: Style.space(32)
              radius: Style.cornerRadius
              color: "transparent"
              border.width: wrow.model.bgPin === modelData ? 2 : 1
              border.color: wrow.model.bgPin === modelData ? root.accent
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

              Image {
                anchors.fill: parent
                anchors.margins: 2
                source: "file://" + modelData
                sourceSize.width: 160
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.bgPick(wrow.model.num, modelData)
              }
            }
          }

          // Add images to this theme: opens its user background folder in Files.
          Rectangle {
            width: Style.space(32)
            height: Style.space(32)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

            Text {
              anchors.centerIn: parent
              text: "+"
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              color: root.muted
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.bgAddImages()
            }
          }
        }
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
    contentWidth: panel.fittedContentWidth(Style.space(780))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a desk is being renamed inline, every key belongs to the editor.
      blocked: root.wsEditing >= 0
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
        else if (t === "H") root.throwAcross(-1)
        else if (t === "L") root.throwAcross(1)
      }

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.space(6)

        // The hero: icon, title, a bar pun — the same heading layout as the stock
        // panels (Dave, 2026-09-01, holding up Display / SUN BLAST as the model),
        // with the apply/cancel buttons riding its trailing edge.
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, headerActions.height)

          Text {
            id: heroIcon
            text: root.iconHero
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: headerActions.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Barbarian"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.mottos[root.motto % root.mottos.length].toUpperCase()
              textFormat: Text.PlainText
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
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

        // Hero to toggle: space(8) on top of the column's space(6) makes the
        // stock panels' space(14) gap.
        Item { width: 1; height: Style.space(8) }

        // Where the workspaces strip lives on the bar — the same chip toggle the seat
        // panel's model picker wears. Staged like every other change: Enter or
        // click-away applies, Escape forgets.
        Row {
          id: modeRow
          width: parent.width
          spacing: Style.space(10)

          readonly property real chipWidth: (width - spacing * 2) / 3

          Button {
            width: modeRow.chipWidth
            text: "Workspaces left"
            bordered: true
            selected: root.mode === "1"
            foreground: root.foreground
            background: bar ? bar.background : Color.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            onClicked: root.setMode("1")
          }
          Button {
            width: modeRow.chipWidth
            text: "Workspaces centre"
            bordered: true
            selected: root.mode === "2"
            foreground: root.foreground
            background: bar ? bar.background : Color.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            onClicked: root.setMode("2")
          }
          Button {
            width: modeRow.chipWidth
            text: "Workspaces off"
            bordered: true
            selected: root.mode === "3"
            foreground: root.foreground
            background: bar ? bar.background : Color.background
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            onClicked: root.setMode("3")
          }
        }

        Item { width: 1; height: Style.space(8) }

        PanelSeparator { width: parent.width; foreground: root.accent; strength: 0.18 }

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

          readonly property real colWidth: (width - spacing * 4 - 2) / 3

          // Slot one: the strip in mode 1, otherwise the bar's left icons.
          Column {
            id: col0
            width: laneRow.colWidth
            spacing: 0

            Text {
              width: parent.width
              text: root.mode === "1" ? "WORKSPACES" : "LEFT"
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              topPadding: 0
              bottomPadding: Style.space(8)
              font.family: root.fontFamily
              // Same spec as the stock PanelSectionHeader (audio's OUTPUT et al).
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.muted
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            }

            Item { width: 1; height: Style.space(4) }

            LaneList {
              id: lviewL
              lane: "L"
              others: [lviewC, lviewR]
              visible: root.mode !== "1"
            }

            DeskList { width: parent.width; visible: root.mode === "1" }
          }

          Rectangle {
            width: 1
            height: Math.max(col0.height, Math.max(col1.height, col2.height))
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          // Slot two: the strip in mode 2 (stock), otherwise the bar's centre icons.
          Column {
            id: col1
            width: laneRow.colWidth
            spacing: 0

            Text {
              width: parent.width
              text: root.mode === "2" ? "WORKSPACES" : "MIDDLE"
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              topPadding: 0
              bottomPadding: Style.space(8)
              font.family: root.fontFamily
              // Same spec as the stock PanelSectionHeader (audio's OUTPUT et al).
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.muted
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            }

            Item { width: 1; height: Style.space(4) }

            LaneList {
              id: lviewC
              lane: "C"
              others: [lviewL, lviewR]
              visible: root.mode !== "2"
            }

            DeskList { width: parent.width; visible: root.mode === "2" }
          }

          Rectangle {
            width: 1
            height: Math.max(col0.height, Math.max(col1.height, col2.height))
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          // Slot three: always the bar's right icons.
          Column {
            id: col2
            width: laneRow.colWidth
            spacing: 0

            Text {
              width: parent.width
              text: "RIGHT"
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              topPadding: 0
              bottomPadding: Style.space(8)
              font.family: root.fontFamily
              // Same spec as the stock PanelSectionHeader (audio's OUTPUT et al).
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.muted
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            }

            Item { width: 1; height: Style.space(4) }

            LaneList {
              id: lviewR
              lane: "R"
              others: [lviewL, lviewC]
            }
          }
        }

        Text {
          width: parent.width
          // Breathing room above, centred under the three columns (Dave, 2026-09-01).
          topPadding: Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          text: "drag rows, across too  ·  eye / x hides  ·  desks: click goes there,  saves,  restores  ·  Enter applies"
          textFormat: Text.PlainText
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.muted
        }
      }
    }
  }
}
