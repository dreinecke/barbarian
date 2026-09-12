import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
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
// ICON-ONLY MODE since 2026-09-12 (Dave: a toggle "by the tick and cross" that shows
// "the tray icon sections as a horizontal row of icons without the name"): three rows
// in the bar's own order, each placed as it sits on the bar — the left lane's tiles
// hug the left edge, the right lane's the right edge, the strip's row (Dave, the same
// day: "Workspaces | Enterprise Webscape Personal ...") shows the desks as chips in
// the middle. Tiles drag along a row to reorder and onto another row to change
// lanes; a right-click opens a small menu with the name and the hide/show (delete,
// for a spacer) that the eye and x did in list mode; hovering shows the name. A desk
// chip goes to the desk on click and offers the desk row's buttons on right-click
// (background, rename in place, save, restore). The keys follow the layout: h/l walk
// a row, j/k hop rows, H/L carry, J/K throw. The
// choice is a view preference, not a bar change — it is written to
// ~/.local/state/omarchy/barbarian.json the moment it flips (shell.json would do, but
// the shell watches that file and would rebuild the bar under the open panel), so it
// survives Escape and the next opening.
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
  readonly property string addScript:
    Qt.resolvedUrl("bin/ws-bg-add").toString().replace(/^file:\/\//, "")
  readonly property string removeScript:
    Qt.resolvedUrl("bin/ws-bg-remove").toString().replace(/^file:\/\//, "")
  // Dave's own background images live under here (ws-bg-add copies into it); only these get
  // the × — a theme's shipped images belong to the omarchy package.
  readonly property string userBgDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds/"
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

  // The view toggle's glyph (Material Design's view-grid, the block the bar's own
  // icons come from) — the button stays lit while icon-only mode is on.
  readonly property string iconGrid: "󰕰"

  // Icon-only mode (see the header). Restored from the state file on load, written
  // there by setIconsOnly — never staged, never part of apply.
  property bool iconsOnly: false
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/barbarian.json"
  // The small menu a right-click opens in icon-only mode (on a tile or a desk chip):
  // its heading, its choices — { glyph, label, note, enabled, act } — and which choice
  // the keyboard cursor sits on.
  property bool tileMenuOpen: false
  property int menuCursor: 0
  property string menuLabel: ""
  property var menuChoices: []
  // Icon-only mode's rows: the tile height, the padding between a tile and the rules
  // above and below it (Dave, 2026-09-12: triple the first cut's six), and so the
  // height of a row between its rules.
  readonly property int tileHeight: Style.space(30)
  readonly property int rowPad: Style.space(18)
  readonly property int rowSlotHeight: tileHeight + rowPad * 2

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
  // Where the workspaces strip sits on the bar — Barbarian's MODE (Dave, 2026-09-01;
  // the third option was a typo for "right", not "off"): "1" strip far left, icons
  // centre + right · "2" icons left, strip centre (stock) · "3" icons left + centre,
  // strip far right. Derived from shell.json on every open and applied on close.
  property string mode: "2"
  // The strip's widget id as found in the layout (tinkerbell.workspaces here,
  // omarchy.workspaces stock) — the apply script moves it whole between sections.
  property string wsWidgetId: ""
  // The background picker (Dave, 2026-09-01): which desk's thumbnail strip is open
  // (-1 = none), and the current theme's background images to offer.
  property int bgPicking: -1
  property string bgPickingName: ""
  property string bgPickingPin: ""
  property var bgThemeList: []
  // How many spacers were deleted this session — the apply script drops that many
  // unnamed spacer entries (the only widget it may delete, mirroring the minting).
  property int spacerDeletes: 0
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
      "omarchy.spacer": "Spacer",
      "io.github.idarius.homeassistant": "Home Assistant",
      "io.github.thisisgm.omapods": "AirPods"
    }
    if (known[wid] !== undefined) return known[wid]
    // Unknown ids fall back to their id's last segment, Title Cased like the rest —
    // the mixed casing bugged Dave (2026-09-01).
    var tail = String(wid).split(".").pop().replace(/-/g, " ")
    return tail.replace(/\b[a-z]/g, function(c) { return c.toUpperCase() })
  }

  // The glyph each widget wears on the bar (Dave, 2026-09-01: "🎧 Audio" not "Audio"),
  // same icon font the bar itself uses. Unknown ids get no glyph, and the fixed-width
  // icon slot keeps the names aligned either way. In icon-only mode a blank tile would
  // be unusable, so an unknown id wears its monogram there (monogramFor) instead.
  function iconFor(wid) {
    var icons = {
      "io.github.idarius.homeassistant": "󰟐",
      "kokd.remote-desktop": "󰢹",
      "io.github.kristoferlund.webcam": "󰄀",
      "nixfred.blip": "󰭻",
      "digitalfrost84.auto-dark-mode": "󰔎",
      "tinkerbell.reptile": "󱔎",
      "io.github.thisisgm.omapods": "󱡏",
      "omarchy.tray": "󰍜",
      "tinkerbell.tray": "󰍜",
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

  // Up to two letters standing in for a missing glyph: the initials of a two-word
  // name ("Remote Desktop" → RD), the first two letters of a one-word name.
  function monogramFor(label) {
    var words = String(label || "").split(/\s+/).filter(function(w) { return w !== "" })
    if (words.length === 0) return "?"
    if (words.length === 1) return words[0].slice(0, 2)
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase()
  }

  // Flip the view and persist it at once — a preference, not a staged change, so it
  // does not dirty the panel and Escape cannot lose it.
  function setIconsOnly(on) {
    if (on === iconsOnly) return
    iconsOnly = on
    stateFile.setText(JSON.stringify({ view: on ? "icons" : "list" }, null, 2) + "\n")
  }

  function restoreView(raw) {
    var state = {}
    try { state = JSON.parse(String(raw || "{}")) } catch (e) { state = {} }
    iconsOnly = state.view === "icons"
  }

  // The menu opens under the right-clicked item with its choices built on the spot —
  // each one's `act` closes over what it needs, and the menu closes on every choice,
  // so nothing in it can go stale.
  function openMenu(label, choices, anchorItem) {
    menuLabel = label
    menuChoices = choices
    menuCursor = 0
    var p = anchorItem.mapToItem(keyCatcher, 0, anchorItem.height)
    tileMenu.x = Math.max(0, Math.min(p.x, keyCatcher.width - tileMenu.width))
    tileMenu.y = p.y
    tileMenu.open()
  }

  // A tile's menu: the eye's hide/show and, for a spacer, the x's delete.
  function openTileMenu(lane, i, slotItem) {
    var m = modelFor(lane)
    if (i < 0 || i >= m.count) return
    var r = m.get(i)
    curLane = lane
    cursor = i
    var choices = [{ glyph: r.hid ? iconEye : iconEyeSlash, label: r.hid ? "Show" : "Hide",
                     enabled: true, act: function() { toggleHidden(lane, i) } }]
    if (r.wid === "omarchy.spacer")
      choices.push({ glyph: iconX, label: "Delete", enabled: true,
                     act: function() { removeSpacer(lane, i) } })
    openMenu(r.label, choices, slotItem)
  }

  // A desk chip's menu: the desk row's buttons — background, rename (where renaming
  // exists on this machine), save, and restore, which stays listed but inert without a
  // recording, as the row's dimmed button does.
  function openDeskMenu(i, chipItem) {
    if (i < 0 || i >= lmW.count) return
    var d = lmW.get(i)
    var n = d.num, name = d.name, pin = d.bgPin, hasSnap = d.hasSnap
    var choices = [{ glyph: iconImage, label: "Background", enabled: true,
                     act: function() { openBgPicker(n, name, pin) } }]
    if (canRename)
      choices.push({ glyph: iconPencil, label: "Rename", enabled: true,
                     act: function() { wsEditing = i } })
    choices.push({ glyph: iconSave, label: "Save layout", enabled: true,
                   act: function() { wsSave(n) } })
    choices.push({ glyph: iconRestore, label: "Restore layout", note: hasSnap ? "" : "no recording",
                   enabled: hasSnap, act: function() { wsRestore(n) } })
    openMenu(name, choices, chipItem)
  }

  function menuChoose(i) {
    var choice = menuChoices[i]
    tileMenu.close()
    if (choice && choice.enabled) choice.act()
  }

  function menuMove(delta) {
    menuCursor = Math.max(0, Math.min(menuChoices.length - 1, menuCursor + delta))
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
    return mode === "1" ? ["C", "R"] : mode === "2" ? ["L", "R"] : ["L", "C"]
  }

  // Switching mode moves the strip; the icon lane that loses its column empties into
  // its neighbour so no icon is stranded in an invisible lane.
  function setMode(m) {
    if (m === mode) return
    if (m === "1") drainLane(lmL, lmC)
    else if (m === "2") drainLane(lmC, lmL)
    else if (m === "3") drainLane(lmR, lmC)
    mode = m
    var lanes = laneOrder()
    if (lanes.indexOf(curLane) < 0) { curLane = lanes[0]; cursor = 0 }
    dirty = true
  }
  // "+ spacer" (Dave, 2026-09-01): add a new spacer row to a lane — at its end, or at
  // `at` when given (the right lane's + tile sits at the lane's start) — staged like
  // any other change. Spacers are the one widget with fungible instances, so the apply
  // script mints one when the bar has fewer than the panel asks for.
  function addSpacer(lane, at) {
    var m = modelFor(lane)
    var row = { wid: "omarchy.spacer", label: prettyName("omarchy.spacer"),
                glyph: iconFor("omarchy.spacer"), hid: false, lit: true }
    if (at === undefined) m.append(row)
    else m.insert(Math.max(0, Math.min(m.count, at)), row)
    dirty = true
  }

  // The x on a spacer row (Dave, 2026-09-01): spacers are removable outright, not
  // just parkable — a deleted one is minted back with one click on "+ spacer".
  function removeSpacer(lane, i) {
    var m = modelFor(lane)
    if (i < 0 || i >= m.count || m.get(i).wid !== "omarchy.spacer") return
    m.remove(i)
    spacerDeletes++
    if (curLane === lane) cursor = Math.max(0, Math.min(m.count - 1, cursor))
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
  function openBgPicker(n, name, pin) {
    console.log("BARB openBgPicker", n, name, pin)
    bgPickingName = name
    bgPickingPin = pin
    bgPicking = n
  }

  // Pin desk n's wallpaper (or "default" to unpin). ws-bg-pick moves the pin file and
  // repaints immediately if n is the desk on screen; the row updates optimistically,
  // and the picker view hands back to the columns.
  function bgPick(n, path) {
    wsActProc.command = ["sh", "-c",
      '"' + pickScript + '" ' + n + " " + JSON.stringify(path)]
    wsActProc.running = true
    var m = rowForWs(n)
    if (m >= 0) lmW.setProperty(m, "bgPin", path === "default" ? "" : path)
    bgPickingPin = path === "default" ? "" : path
    bgPicking = -1
  }

  // The + chip: the shell's own image grid over Pictures and Downloads (thumbnails, type to
  // filter); the pick is copied into this theme's user background folder and pinned to the
  // desk whose picker was open (Dave, 2026-09-03 — until then the chip opened Files on that
  // folder, stock `omarchy theme bg install`, and left the rest to hand). bin/ws-bg-add does
  // all of it and takes as long as Dave takes to choose, so it runs detached and the panel
  // closes first: the grid fills the screen, and the desk repaints the moment he picks.
  function bgAddImage() {
    var n = bgPicking
    if (n < 0) return
    bgPicking = -1
    close()
    Quickshell.execDetached(["sh", "-c", '"' + addScript + '" ' + n + " >/dev/null 2>&1"])
  }

  // The × on an image tile (Dave, 2026-09-03: "Hover reveals an x in top right. And sets the
  // background to auto"): the image leaves the theme — every desk pinned to it goes back to
  // Auto and the file goes to the trash (bin/ws-bg-remove). The strip and the rows are updated
  // here at once, and the picker view stays open.
  function bgRemove(path) {
    wsActProc.command = ["sh", "-c", '"' + removeScript + '" ' + JSON.stringify(path)]
    wsActProc.running = true
    bgThemeList = bgThemeList.filter(function(p) { return p !== path })
    for (var i = 0; i < lmW.count; i++)
      if (lmW.get(i).bgPin === path) lmW.setProperty(i, "bgPin", "")
    if (bgPickingPin === path) bgPickingPin = ""
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
      // A strip parked in the sidecar (the retired "off" mode) or missing entirely is
      // treated as centre — the next apply brings it back there.
      mode = inL ? "1" : inR ? "3" : "2"
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
      var sol = [{ name: "Black", hex: "#000000" }]
      var seen = { "#000000": true }
      // No red/cyan/magenta — "those tend to look terrible for this kind of
      // purpose" (Dave, 2026-09-01).
      var ckeys = ["background", "accent", "muted", "yellow", "green", "blue"]
      var cl = String(tail4b[1].split("---PINS---")[0] || "").split("\n")
      for (var ci = 0; ci < cl.length; ci++) {
        var cm = cl[ci].match(/^\s*([A-Za-z_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (!cm || ckeys.indexOf(cm[1]) < 0) continue
        var hx = cm[2].toLowerCase()
        if (seen[hx]) continue
        seen[hx] = true
        sol.push({ name: cm[1].charAt(0).toUpperCase() + cm[1].slice(1), hex: hx })
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
    tileMenu.close()
    spacerDeletes = 0
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
        + (mode === "1" ? "left" : mode === "2" ? "center" : "right"))
    for (i = 0; i < spacerDeletes; i++) argv.push("DEL:omarchy.spacer")
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
        "echo ---PINS---; tn=\"$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null)\"; for f in \"$HOME/.config/omarchy/workspace-backgrounds/$tn\"/ws*.*; do [ -e \"$f\" ] && echo \"$f|$(readlink -f \"$f\")\"; done; true"]
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

  // The view preference. Written whole on every flip; a missing file means list mode.
  // Watched, so a flip made elsewhere (a second screen's panel, a hand edit) shows
  // here without a shell restart.
  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    atomicWrites: true
    watchChanges: true
    onLoaded: root.restoreView(text())
    onFileChanged: reload()
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
          anchors.right: spacerX.left
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

        // Spacers only: an x that deletes the row outright (hide would just park it).
        // Clicked through the drag area's hit test, like the eye.
        Text {
          id: spacerX
          visible: wrap.model.wid === "omarchy.spacer"
          width: visible ? implicitWidth : 0
          anchors.right: eye.left
          anchors.rightMargin: visible ? Style.space(10) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.iconX
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.foreground
          opacity: 0.55
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
              && p.y > -Style.space(8) && p.y < eye.height + Style.space(8)) {
            root.toggleHidden(list.lane, wrap.index)
            return
          }
          if (spacerX.visible) {
            var q = dragArea.mapToItem(spacerX, mouse.x, mouse.y)
            if (q.x > -Style.space(6) && q.x < spacerX.width + Style.space(6)
                && q.y > -Style.space(8) && q.y < spacerX.height + Style.space(8))
              root.removeSpacer(list.lane, wrap.index)
          }
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

  // "+ spacer" at the foot of a lane: drawn exactly like a spacer row in the list —
  // same card, same label position — with a + in the glyph slot and no eye or grip
  // (Dave, 2026-09-01). Clicking stages a new spacer above it.
  component AddSpacer: Item {
    property string lane: "R"
    width: parent.width
    height: Style.space(34)

    Rectangle {
      width: parent.width
      height: Style.space(30)
      y: Style.space(2)
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                     addArea.containsMouse ? 0.10 : 0.04)

      Item {
        id: addGlyphSlot
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(22)
        height: addPlus.implicitHeight

        Text {
          id: addPlus
          anchors.centerIn: parent
          text: "+"
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          color: root.foreground
          opacity: addArea.containsMouse ? 0.85 : 0.4
        }
      }

      Text {
        anchors.left: addGlyphSlot.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Spacer"
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        color: root.foreground
        opacity: addArea.containsMouse ? 0.9 : 0.45
      }
    }

    MouseArea {
      id: addArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.addSpacer(parent.lane)
    }
  }

  // A glyph centred on its ink rather than its line box: an icon font's glyphs sit
  // anywhere in their em box, so centring the Text item leaves them visibly off (Dave,
  // 2026-09-12: "pixel perfect visually centered vertically between the lines").
  // TextMetrics measures the ink, and the position lands on whole pixels.
  component InkGlyph: Item {
    id: ink

    property alias text: glyph.text
    property alias font: glyph.font
    property alias color: glyph.color

    TextMetrics {
      id: metrics
      font: glyph.font
      text: glyph.text
    }

    Text {
      id: glyph
      textFormat: Text.PlainText
      x: Math.round(ink.width / 2 - (metrics.tightBoundingRect.x + metrics.tightBoundingRect.width / 2))
      y: Math.round(ink.height / 2 - (glyph.baselineOffset + metrics.tightBoundingRect.y
                                      + metrics.tightBoundingRect.height / 2))
    }
  }

  // Icon-only mode's lane row: the same lane model as a LaneList, laid out as one
  // horizontal strip of glyph tiles placed as the lane sits on the bar — `align` puts
  // the strip at the left edge, the centre or the right edge. Drag along the row
  // reorders live; drag onto another row and release, and the tile changes lanes at
  // the drop spot. Right-click opens the tile menu, hovering shows the name the tile
  // no longer carries. The + tile that stages a spacer sits at the row's far end away
  // from the strip — right for the left lane, left for the right lane (Dave,
  // 2026-09-12) — and beside the strip when the strip is centred; the empty drop slot
  // faces the same way as the + tile.
  component IconRow: Item {
    id: irow

    property string lane: "R"
    // "left", "center" or "right".
    property string align: "left"
    // The other icon rows, for the cross-row drop test (their own `visible` says
    // whether they are on screen in this mode).
    property var others: []
    readonly property Item strip: stripView
    readonly property bool dragging: stripView.dragging

    width: parent.width
    height: root.rowSlotHeight

    Component {
      id: leadSlot
      Item { width: stripView.slotWidth; height: stripView.height }
    }

    ListView {
      id: stripView

      property bool dragging: false
      // Tiles squeeze together once a lane outgrows the row (a mode switch drains one
      // lane into another), down to a floor that still holds the glyph; beyond about
      // thirty tiles the row overflows.
      readonly property int slotWidth: Math.max(Style.space(22), Math.min(Style.space(32),
        Math.floor(irow.width / (count + 2))))

      x: irow.align === "right" ? irow.width - width
       : irow.align === "center" ? Math.round((irow.width - width - addTile.width) / 2) : 0
      y: 0
      orientation: ListView.Horizontal
      // One empty slot beyond the last tile — before the first, on the right lane —
      // always: room to drop something at that end, and an empty lane is still a target.
      header: irow.align === "right" ? leadSlot : null
      width: (count + 1) * slotWidth
      height: irow.height
      clip: false
      interactive: false
      spacing: 0
      model: irow.lane === "L" ? lmL : irow.lane === "C" ? lmC : lmR

      move: Transition { NumberAnimation { properties: "x"; duration: 110 } }
      moveDisplaced: Transition { NumberAnimation { properties: "x"; duration: 110 } }
      displaced: Transition { NumberAnimation { properties: "x"; duration: 110 } }

      delegate: Item {
        id: slot
        required property var model
        required property int index
        readonly property bool spacer: model.wid === "omarchy.spacer"

        width: stripView.slotWidth
        height: stripView.height
        z: tileArea.drag.active ? 10 : 0

        // A spacer's tile is simply empty (Dave, 2026-09-12: no outline) — the hover
        // name and the menu heading say what it is.
        Rectangle {
          id: tile
          x: Style.space(2)
          y: root.rowPad
          width: slot.width - Style.space(4)
          height: root.tileHeight
          radius: Style.cornerRadius
          color: tileArea.drag.active
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            : (root.curLane === irow.lane && root.cursor === slot.index) || tileArea.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

          Behavior on color { ColorAnimation { duration: 80 } }

          InkGlyph {
            anchors.fill: parent
            text: slot.spacer ? "" : slot.model.glyph !== "" ? slot.model.glyph
                                                             : root.monogramFor(slot.model.label)
            font.family: root.fontFamily
            font.pixelSize: slot.model.glyph !== "" ? Style.font.title : Style.font.caption
            font.bold: slot.model.glyph === ""
            color: root.foreground
            // The glyph is the whole tile here, so it wears the label's full brightness;
            // faded = drawing nothing right now, as in list mode.
            opacity: slot.model.lit ? 1 : 0.25
          }

          // Parked off the bar: the slashed eye in the corner (the label's strikethrough
          // has no label to live on in this mode).
          Text {
            visible: slot.model.hid
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(1)
            text: root.iconEyeSlash
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.foreground
            opacity: 0.8
          }
        }

        PanelToolTip {
          visible: tileArea.containsMouse && !tileArea.drag.active && !root.tileMenuOpen
          text: slot.model.label
          fontFamily: root.fontFamily
        }

        // Left button only: the right button falls through to the TapHandler below, so a
        // right-click can never start a drag.
        MouseArea {
          id: tileArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          drag.target: tile
          drag.axis: Drag.XAndYAxis
          drag.onActiveChanged: stripView.dragging = drag.active

          onContainsMouseChanged: if (containsMouse) { root.curLane = irow.lane; root.cursor = slot.index }
          onPositionChanged: {
            if (!drag.active) return
            var c = tile.mapToItem(stripView, tile.width / 2, tile.height / 2)
            if (c.y >= 0 && c.y <= stripView.height) {
              // Still over the home row: live-reorder. The content item's x counts
              // from the first tile whichever side the empty slot is on.
              var centerX = tile.mapToItem(stripView.contentItem, tile.width / 2, 0).x
              var to = Math.max(0, Math.min(stripView.count - 1,
                                            Math.floor(centerX / stripView.slotWidth)))
              if (to !== slot.index) root.moveItem(irow.lane, slot.index, to)
            }
          }
          onReleased: {
            stripView.dragging = false
            // Dropped over another visible row? The tile changes lanes there, at the
            // slot under it — measured in that row's own slot width.
            for (var oi = 0; oi < irow.others.length; oi++) {
              var other = irow.others[oi]
              if (!other || !other.visible) continue
              var o = tile.mapToItem(other.strip, tile.width / 2, tile.height / 2)
              if (o.y >= -Style.space(6) && o.y <= other.strip.height + Style.space(6)) {
                var ox = tile.mapToItem(other.strip.contentItem, tile.width / 2, 0).x
                var at = Math.max(0, Math.min(other.strip.count,
                                              Math.round(ox / other.strip.slotWidth)))
                root.moveAcross(irow.lane, slot.index, other.lane, at)
                break
              }
            }
            tile.x = Style.space(2); tile.y = root.rowPad
          }
          onCanceled: { stripView.dragging = false; tile.x = Style.space(2); tile.y = root.rowPad }
        }

        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: root.openTileMenu(irow.lane, slot.index, slot)
        }
      }
    }

    // The + tile: a spacer-shaped tile that stages a new spacer in this lane, at the
    // end the tile sits at.
    Item {
      id: addTile
      x: irow.align === "right" ? 0
       : irow.align === "left" ? irow.width - width : stripView.x + stripView.width
      y: 0
      width: stripView.slotWidth
      height: irow.height

      Rectangle {
        x: Style.space(2)
        y: root.rowPad
        width: parent.width - Style.space(4)
        height: root.tileHeight
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                       addArea.containsMouse ? 0.10 : 0.04)

        InkGlyph {
          anchors.fill: parent
          text: "+"
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          color: root.foreground
          opacity: addArea.containsMouse ? 0.85 : 0.4
        }
      }

      PanelToolTip {
        visible: addArea.containsMouse
        text: "Add a spacer"
        fontFamily: root.fontFamily
      }

      MouseArea {
        id: addArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addSpacer(irow.lane, irow.align === "right" ? 0 : undefined)
      }
    }
  }

  // Icon-only mode's workspaces row: the desks as chips, placed as the strip sits on
  // the bar. A click goes to the desk; a right-click opens the desk menu (background,
  // rename, save, restore); a rename edits the chip in place. No dragging — a desk's
  // number is load-bearing (see fillWorkspaces).
  component DeskRow: Item {
    id: drow

    // "left", "center" or "right".
    property string align: "center"

    width: parent.width
    height: root.rowSlotHeight

    Row {
      id: chips
      x: drow.align === "right" ? drow.width - width
       : drow.align === "center" ? Math.round((drow.width - width) / 2) : 0
      y: root.rowPad
      spacing: Style.space(4)

      Repeater {
        model: lmW

        delegate: Rectangle {
          id: chip
          required property var model
          required property int index
          readonly property bool editing: root.wsEditing === index

          width: editing ? Style.space(150) : chipLabel.implicitWidth + Style.space(20)
          height: root.tileHeight
          radius: Style.cornerRadius
          color: chip.model.focused
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            : chipArea.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

          Behavior on color { ColorAnimation { duration: 80 } }

          // Centred on the capital-letter band rather than the line box, so every name
          // sits at the same height whatever its descenders, and a capital is centred
          // between the rules like the glyphs beside it.
          TextMetrics {
            id: capBand
            font: chipLabel.font
            text: "H"
          }

          Text {
            id: chipLabel
            visible: !chip.editing
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(chip.height / 2 - (chipLabel.baselineOffset + capBand.tightBoundingRect.y
                                             + capBand.tightBoundingRect.height / 2))
            text: chip.model.name
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
          }

          TextField {
            id: chipEdit
            visible: chip.editing
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
            onAccepted: { root.wsRename(chip.model.num, text); root.wsEditing = -1 }
            Keys.onEscapePressed: root.wsEditing = -1
          }

          // The rename lands here from the menu: fill the field and hand it the keys.
          // Only the row on screen answers — the other two slots hold hidden twins.
          Connections {
            target: root
            function onWsEditingChanged() {
              if (root.wsEditing !== chip.index || !drow.visible) return
              chipEdit.text = chip.model.name
              chipEdit.forceActiveFocus()
              chipEdit.selectAll()
            }
          }

          MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: !chip.editing
            cursorShape: Qt.PointingHandCursor
            onClicked: root.wsFocus(chip.model.num)
          }

          TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: !chip.editing
            onTapped: root.openDeskMenu(chip.index, chip)
          }
        }
      }
    }
  }

  // One line of the menu: a glyph and a word, lit while the menu's cursor is on it
  // (hover moves the cursor, the cursor paints — the panel kit's rule). An inert
  // choice stays listed, dimmed, with a muted note saying why.
  component MenuChoice: CursorSurface {
    id: choice

    property string glyph: ""
    property string label: ""
    property string note: ""
    property bool selected: false

    signal chosen()
    signal hovered()

    width: parent.width
    implicitHeight: Style.space(30)
    foreground: root.foreground
    accent: root.accent
    hasCursor: selected
    opacity: enabled ? 1 : 0.4

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: choice.glyph
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: root.foreground
        opacity: 0.7
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: choice.label
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        color: root.foreground
      }
    }

    Text {
      visible: choice.note !== ""
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: choice.note
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: root.muted
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: choice.hovered()
      onClicked: choice.chosen()
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

        Rectangle {
          id: wcard
          width: wrow.width
          // Fixed row height, NOT wrow.height - the delegate grows to hold the open
          // background picker, and a card bound to it ballooned over the rows below
          // (Dave's "jumbled" screenshot, 2026-09-01).
          height: Style.space(30)
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
            onVisibleChanged: if (visible && wrow.model) { text = wrow.model.name; forceActiveFocus(); selectAll() }
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
            // No rename on this machine, no gap for it: skip the hidden pencil (anchors keep
            // an invisible item's width — the MacBook showed an empty column, 2026-09-01).
            anchors.right: root.canRename ? wpencil.left : wsave.left
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.iconImage
            tooltipText: "Background"
            // Uniform with the other desk buttons: with every desk pinned, the old
            // accent-when-pinned tint was always on — a signal carrying nothing
            // (Dave queried the odd colour, 2026-09-01). The picker's highlighted
            // swatch shows the pin state instead.
            foreground: Qt.darker(root.foreground, 1.8)
            hoverColor: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: { console.log("BARB wimg clicked", wrow.model.num); root.openBgPicker(wrow.model.num, wrow.model.name, wrow.model.bgPin) }
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
      // Escape CANCELS (nothing written); Enter and click-away APPLY. While the tile
      // menu is up, Escape shuts it and Enter takes its choice; while the background
      // picker is up, both just hand back to the columns.
      onCloseRequested: {
        if (root.tileMenuOpen) tileMenu.close()
        else if (root.bgPicking >= 0) root.bgPicking = -1
        else root.cancelAndClose()
      }
      onActivateRequested: {
        if (root.tileMenuOpen) root.menuChoose(root.menuCursor)
        else if (root.bgPicking >= 0) root.bgPicking = -1
        else root.acceptAndClose()
      }
      // x (PanelKeyCatcher's delete key) hides/shows the selected row.
      onDeleteRequested: if (root.bgPicking < 0 && !root.tileMenuOpen) root.toggleHidden(root.curLane, root.cursor)
      // j/k (dy) walk a column, h/l (dx) hop between the two. In icon-only mode the
      // keys follow the layout: h/l walk the row, j/k hop between rows. In the tile
      // menu, j/k walk its choices.
      onMoveRequested: function(dx, dy) {
        if (root.tileMenuOpen) { if (dy !== 0) root.menuMove(dy); return }
        if (root.bgPicking >= 0) return
        if (root.iconsOnly) {
          if (dx !== 0) root.moveCursor(dx)
          if (dy !== 0) root.switchLane(dy)
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        if (dx !== 0) root.switchLane(dx)
      }
      // J/K carry the selected row up/down; H/L throw it to the other column. In
      // icon-only mode H/L carry the tile along its row and J/K throw it to the row
      // above or below.
      onTextKey: function(t) {
        if (root.bgPicking >= 0 || root.tileMenuOpen) return
        if (root.iconsOnly) {
          if (t === "L") root.moveItem(root.curLane, root.cursor, root.cursor + 1)
          else if (t === "H") root.moveItem(root.curLane, root.cursor, root.cursor - 1)
          else if (t === "J") root.throwAcross(1)
          else if (t === "K") root.throwAcross(-1)
          return
        }
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

            // The view toggle: lit (hover fill, accent glyph) while icon-only mode is on.
            PanelActionButton {
              iconText: root.iconGrid
              tooltipText: root.iconsOnly ? "Show names" : "Icons only"
              hasCursor: root.iconsOnly
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.iconSmall
              onClicked: root.setIconsOnly(!root.iconsOnly)
            }

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
          visible: root.bgPicking < 0
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
            text: "Workspaces right"
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

        // Icon-only mode draws its own top rule inside its column, so the column's
        // spacing cannot open a gap above the first row that the rows below lack.
        PanelSeparator {
          width: parent.width
          foreground: root.accent
          strength: 0.18
          visible: !iconRows.visible
        }

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
          visible: root.bgPicking < 0 && !root.iconsOnly
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

            AddSpacer { lane: "L"; visible: root.mode !== "1" }

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

            AddSpacer { lane: "C"; visible: root.mode !== "2" }

            DeskList { width: parent.width; visible: root.mode === "2" }
          }

          Rectangle {
            width: 1
            height: Math.max(col0.height, Math.max(col1.height, col2.height))
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          // Slot three: the strip in mode 3, otherwise the bar's right icons.
          Column {
            id: col2
            width: laneRow.colWidth
            spacing: 0

            Text {
              width: parent.width
              text: root.mode === "3" ? "WORKSPACES" : "RIGHT"
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
              visible: root.mode !== "3"
            }

            AddSpacer { lane: "R"; visible: root.mode !== "3" }

            DeskList { width: parent.width; visible: root.mode === "3" }
          }
        }

        // Icon-only mode's body: three rows in the bar's own order — the strip's row
        // where the mode puts it, the icon lanes in theirs — each placed as it sits on
        // the bar, a rule between them. A slot lifts itself while its tile is dragged,
        // so the tile paints over the rows below.
        Column {
          id: iconRows
          visible: root.bgPicking < 0 && root.iconsOnly
          width: parent.width
          spacing: 0

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          // Slot one: the strip in mode 1, otherwise the bar's left icons.
          Item {
            width: parent.width
            height: root.rowSlotHeight
            z: rowL.dragging ? 5 : 0

            IconRow {
              id: rowL
              lane: "L"
              align: "left"
              others: [rowC, rowR]
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode !== "1"
            }

            DeskRow {
              align: "left"
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode === "1"
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          // Slot two: the strip in mode 2 (stock), otherwise the bar's centre icons.
          Item {
            width: parent.width
            height: root.rowSlotHeight
            z: rowC.dragging ? 5 : 0

            IconRow {
              id: rowC
              lane: "C"
              align: "center"
              others: [rowL, rowR]
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode !== "2"
            }

            DeskRow {
              align: "center"
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode === "2"
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          // Slot three: the strip in mode 3, otherwise the bar's right icons.
          Item {
            width: parent.width
            height: root.rowSlotHeight
            z: rowR.dragging ? 5 : 0

            IconRow {
              id: rowR
              lane: "R"
              align: "right"
              others: [rowL, rowC]
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode !== "3"
            }

            DeskRow {
              align: "right"
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode === "3"
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }
        }

        // The full-panel background picker (Dave, 2026-09-01: "replace the entire
        // widget area with the selector"): heading with a back affordance, then
        // double-size tiles — Auto, the theme's colours shaped exactly like the
        // image tiles, the theme's images, and the + chip. A click pins and hands
        // straight back to the columns; Escape or the heading goes back untouched.
        Column {
          visible: root.bgPicking >= 0
          width: parent.width
          spacing: 0

          Item {
            width: parent.width
            height: pickHead.implicitHeight

            Text {
              id: pickBack
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "\u2039 back"
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: root.muted
              opacity: backArea.containsMouse ? 1 : 0.6

              MouseArea {
                id: backArea
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.bgPicking = -1
              }
            }

            Text {
              id: pickHead
              width: parent.width
              text: "BACKGROUND \u00b7 " + root.bgPickingName.toUpperCase()
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideMiddle
              topPadding: 0
              bottomPadding: Style.space(8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: root.muted
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          Item { width: 1; height: Style.space(10) }

          Flow {
            id: pickFlow
            width: parent.width
            spacing: Style.space(8)

            // Three tiles to a row, whatever the panel width (Dave, 2026-09-01).
            readonly property real tileW: (width - spacing * 2) / 3
            readonly property real tileH: Math.round(tileW * 0.56)

            Rectangle {
              width: pickFlow.tileW
              height: pickFlow.tileH
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              border.width: root.bgPickingPin === "" ? 2 : 1
              border.color: root.bgPickingPin === "" ? root.accent
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

              Text {
                anchors.centerIn: parent
                text: "Auto"
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.muted
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.bgPick(root.bgPicking, "default")
              }
            }

            Repeater {
              model: root.bgSolids

              delegate: Rectangle {
                required property var modelData
                readonly property bool current:
                  root.bgPickingPin.indexOf("/solids/" + modelData.hex.slice(1) + ".png") >= 0
                readonly property color tileColor: modelData.hex
                width: pickFlow.tileW
                height: pickFlow.tileH
                radius: Style.cornerRadius
                color: tileColor
                border.width: current ? 2 : 1
                border.color: current ? root.accent
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                Text {
                  anchors.centerIn: parent
                  text: modelData.name
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  // Ink picked against THIS tile's colour, not the theme's.
                  color: (parent.tileColor.r * 0.299 + parent.tileColor.g * 0.587
                          + parent.tileColor.b * 0.114) > 0.55 ? "#1a1a1a" : "#e8e8e8"
                  opacity: 0.9
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.bgPick(root.bgPicking, "solid:" + modelData.hex)
                }
              }
            }

            Repeater {
              model: root.bgThemeList

              // ClippingRectangle, so the image respects the rounded corners instead
              // of bleeding square past them (Dave's screenshot, 2026-09-01).
              delegate: ClippingRectangle {
                required property var modelData
                readonly property bool current: root.bgPickingPin === modelData
                readonly property bool removable: String(modelData).indexOf(root.userBgDir) === 0
                width: pickFlow.tileW
                height: pickFlow.tileH
                radius: Style.cornerRadius
                color: "transparent"
                border.width: current ? 2 : 1
                border.color: current ? root.accent
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                Image {
                  anchors.fill: parent
                  source: "file://" + modelData
                  sourceSize.width: 480
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
                MouseArea {
                  id: tileArea
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.bgPick(root.bgPicking, modelData)
                }

                // Hover reveals a × in the top-right corner of one of Dave's own images; a
                // faint dark disc keeps it legible over a bright picture.
                Rectangle {
                  visible: removable && (tileArea.containsMouse || xArea.containsMouse)
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Style.space(8)
                  width: Style.space(26)
                  height: width
                  radius: width / 2
                  color: Qt.rgba(0, 0, 0, xArea.containsMouse ? 0.55 : 0.35)

                  Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    color: xArea.containsMouse ? "#ff6b81" : "#ff3d5a"
                  }
                  MouseArea {
                    id: xArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.bgRemove(modelData)
                  }
                }
              }
            }

            Rectangle {
              width: pickFlow.tileW
              height: pickFlow.tileH
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

              Text {
                anchors.centerIn: parent
                text: "+"
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                color: root.muted
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.bgAddImage()
              }
            }
          }
        }

        Text {
          visible: root.bgPicking < 0
          width: parent.width
          // Breathing room above, centred under the three columns (Dave, 2026-09-01).
          topPadding: Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          text: root.iconsOnly
            ? "drag tiles, across rows too  ·  right-click: hide / show, or a desk's actions  ·  click a desk to go there  ·  Enter applies"
            : "drag rows, across too  ·  eye / x hides  ·  desks: click goes there,  saves,  restores  ·  Enter applies"
          textFormat: Text.PlainText
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.muted
        }
      }

      // The tile menu: the name, then the choices the eye and x offer in list mode. A
      // plain Popup on the panel's own surface that takes no focus of its own — the key
      // catcher above keeps the keyboard and routes Escape, j/k and Enter here while
      // the menu is up, exactly as it does for the background picker. A press anywhere
      // else closes it.
      Popup {
        id: tileMenu
        width: Style.space(220)
        padding: Style.space(4)
        modal: false
        dim: false
        focus: false
        closePolicy: Popup.CloseOnPressOutside
        onOpenedChanged: root.tileMenuOpen = opened

        background: BorderSurface {
          color: Color.popups.background
          borderSpec: Border.flat(Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35), 1)
          radius: Style.cornerRadius
        }

        contentItem: Column {

          // The name, since the tile does not carry it — the columns' heading style.
          Text {
            width: parent.width
            leftPadding: Style.space(8)
            rightPadding: Style.space(8)
            topPadding: Style.space(5)
            bottomPadding: Style.space(5)
            text: root.menuLabel.toUpperCase()
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            color: root.muted
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          Item { width: 1; height: Style.space(3) }

          Repeater {
            model: root.menuChoices

            delegate: MenuChoice {
              required property var modelData
              required property int index
              glyph: modelData.glyph
              label: modelData.label
              note: modelData.note || ""
              enabled: modelData.enabled !== false
              selected: root.menuCursor === index
              onHovered: root.menuCursor = index
              onChosen: root.menuChoose(index)
            }
          }
        }
      }
    }
  }
}
