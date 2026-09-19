import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "." as Reordering

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
// want" it back), and parks it at its lane's far end so the hidden ones sit together
// (see toggleHidden). Files are written ONCE, when the panel closes (Enter, click-away) —
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
// (background, rename in place, save, restore, move, delete). A tile parked off the bar wears the
// theme's urgent colour at the same 55% as a widget drawing nothing — the colour is
// the whole signal, with no badge on the corner. The keys follow the layout: h/l walk
// a row, j/k hop rows, H/L carry, J/K throw. The
// choice is a view preference, not a bar change — it is written to
// ~/.local/state/omarchy/barbarian.json the moment it flips (shell.json would do, but
// the shell watches that file and would rebuild the bar under the open panel), so it
// survives Escape and the next opening.
//
// DESKS since 2026-09-19 (Dave: delete a workspace "through the usual method either right
// click context menu or an action icon depending on the view", reorder them "in the same way
// that it allows you to reorder bar icons", and "ctrl-z to undo the last change you made to
// anything"): desk chips and desk rows drag to reorder, a desk is deleted from its menu or the
// list's bin button after an "are you sure", and both are staged like every bar change.
// bin/ws-renumber applies them — see its header for why each desk is renumbered in place and
// what moves with it. Ctrl+Z / Ctrl+Shift+Z undo and redo everything done while the panel is
// open; the history ends when it closes.
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
  readonly property string restoreBgScript:
    Qt.resolvedUrl("bin/ws-bg-restore").toString().replace(/^file:\/\//, "")
  readonly property string renumberScript:
    Qt.resolvedUrl("bin/ws-renumber").toString().replace(/^file:\/\//, "")
  readonly property string stashScript:
    Qt.resolvedUrl("bin/barbarian-stash").toString().replace(/^file:\/\//, "")
  readonly property string snapDir: Quickshell.env("HOME") + "/.config/omarchy/workspace-layout/snapshots"
  // Dave's own background images live under here (ws-bg-add copies into it); only these get
  // the × — a theme's shipped images belong to the omarchy package.
  readonly property string userBgDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds/"
  // This widget must never list (or reorder away) itself.
  readonly property string selfId: "tinkerbell.arrange"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted
  readonly property color urgent: bar ? bar.urgent : Color.urgent
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
  readonly property string iconTrash: "\uF1F8"

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
  property point menuAnchor: Qt.point(0, 0)
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

  // Desks (Dave, 2026-09-19: delete one, reorder them "in the same way that it allows you to
  // reorder bar icons"). Staged like every bar change and applied on close by bin/ws-renumber,
  // which renumbers the desks in place and moves everything keyed by a desk's number with it.
  // deskSlots: the desks' numbers when the panel opened, smallest first — the Nth desk in the
  // staged order takes the Nth of them. deskMerges: desk number → the desk its windows move to,
  // for each desk deleted this session. canEditDesks: false where the machine's config pins desks
  // to numbers and nothing is installed to renumber it (see fillWorkspaces).
  property var deskSlots: []
  property var deskMerges: ({})
  property bool canEditDesks: false

  // Undo (Dave, 2026-09-19: "ctrl-z to undo the last change you made to anything"). One history
  // for the open panel, oldest first. A staged change is undone by putting back a snapshot of
  // everything staged (captureStaged); a change that happened at once — a rename, a background, a
  // saved layout — by an action that reverses it. Going to a desk and restoring a layout are not
  // changes and are not recorded. changeDepth > 0 while one user action is under way, so the
  // steps it is made of (a hide that also moves the row, a drag that crosses several rows) undo
  // as one.
  property var undoStack: []
  property var redoStack: []
  property int changeDepth: 0
  property string undoNote: ""

  // The "are you sure" card before a desk is deleted.
  property bool confirmOpen: false
  property string confirmMessage: ""
  property var confirmAction: null

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
    iconDrag.reset()
    deskDrag.reset()
    iconsOnly = on
    stateFile.setText(JSON.stringify({ view: on ? "icons" : "list" }, null, 2) + "\n")
  }

  function restoreView(raw) {
    var state = {}
    try { state = JSON.parse(String(raw || "{}")) } catch (e) { state = {} }
    if (iconsOnly !== (state.view === "icons")) { iconDrag.reset(); deskDrag.reset() }
    iconsOnly = state.view === "icons"
  }

  // ── undo ────────────────────────────────────────────────────────────────────────

  function rowsOf(model) {
    var rows = []
    for (var i = 0; i < model.count; i++) rows.push(JSON.parse(JSON.stringify(model.get(i))))
    return rows
  }

  // Only a model that differs is rebuilt, so an undo in one column leaves the others' rows
  // (and anything open in them) alone.
  function refill(model, rows) {
    if (JSON.stringify(rowsOf(model)) === JSON.stringify(rows)) return
    model.clear()
    for (var i = 0; i < rows.length; i++) model.append(rows[i])
  }

  // Everything staged — what apply() would write — plus where the cursor was.
  function captureStaged() {
    var merges = {}
    for (var k in deskMerges) merges[k] = deskMerges[k]
    return { L: rowsOf(lmL), C: rowsOf(lmC), R: rowsOf(lmR), W: rowsOf(lmW), mode: mode,
             spacerDeletes: spacerDeletes, deskMerges: merges, curLane: curLane, cursor: cursor }
  }

  function stagedKey(state) {
    return JSON.stringify([state.L, state.C, state.R, state.W, state.mode, state.spacerDeletes,
                           state.deskMerges])
  }

  function restoreStaged(state) {
    iconDrag.reset()
    deskDrag.reset()
    wsEditing = -1
    refill(lmL, state.L)
    refill(lmC, state.C)
    refill(lmR, state.R)
    refill(lmW, state.W)
    mode = state.mode
    spacerDeletes = state.spacerDeletes
    deskMerges = state.deskMerges
    curLane = state.curLane
    cursor = Math.max(0, Math.min(modelFor(curLane).count - 1, state.cursor))
    dirty = true
  }

  function pushUndo(entry) {
    undoStack = undoStack.concat([entry])
    redoStack = []
  }

  // One user action on the staged arrangement: snapshot first, so undo can put it back. A change
  // made from inside another (toggleHidden moving the row it hid) is part of the outer one.
  function change(label, fn) {
    if (changeDepth > 0) { fn(); return }
    var before = captureStaged()
    changeDepth++
    try { fn() } finally { changeDepth-- }
    if (stagedKey(before) === stagedKey(captureStaged())) return
    pushUndo({ label: label, state: before })
    dirty = true
  }

  // A list-view drag reorders as it goes, so everything from pick-up to drop is one change.
  property var gestureState: null
  function beginGesture() {
    if (gestureState) return
    gestureState = captureStaged()
    changeDepth++
  }
  function endGesture(label) {
    if (!gestureState) return
    var before = gestureState
    gestureState = null
    changeDepth--
    if (stagedKey(before) !== stagedKey(captureStaged())) pushUndo({ label: label, state: before })
  }

  // A change that has already happened outside the panel, with the actions that reverse and
  // repeat it.
  function record(label, undoFn, redoFn) {
    pushUndo({ label: label, undo: undoFn, redo: redoFn })
  }

  function undo() {
    if (iconDrag.busy || deskDrag.busy || gestureState) return
    if (undoStack.length === 0) { say("Nothing to undo"); return }
    var entry = undoStack[undoStack.length - 1]
    undoStack = undoStack.slice(0, -1)
    if (entry.state) {
      var now = captureStaged()
      restoreStaged(entry.state)
      entry = { label: entry.label, state: now }
    } else {
      entry.undo()
    }
    redoStack = redoStack.concat([entry])
    say("Undone: " + entry.label)
  }

  function redo() {
    if (iconDrag.busy || deskDrag.busy || gestureState) return
    if (redoStack.length === 0) { say("Nothing to redo"); return }
    var entry = redoStack[redoStack.length - 1]
    redoStack = redoStack.slice(0, -1)
    if (entry.state) {
      var now = captureStaged()
      restoreStaged(entry.state)
      entry = { label: entry.label, state: now }
    } else {
      entry.redo()
    }
    undoStack = undoStack.concat([entry])
    say("Redone: " + entry.label)
  }

  // What undo and redo did, in the help line for a few seconds and to a screen reader.
  function say(text) {
    undoNote = text
    undoNoteTimer.restart()
    keyCatcher.Accessible.announce(text, Accessible.Polite)
  }

  // ── jobs ────────────────────────────────────────────────────────────────────────

  // The desk actions that change something outside the panel (focus, rename, background, save,
  // restore) run one after another, in the order they were asked for — an undo straight after the
  // change it reverses must not overtake it.
  property var jobs: []
  function runJob(argv) {
    jobs = jobs.concat([argv])
    Qt.callLater(nextJob)
  }
  function nextJob() {
    if (jobProc.running || jobs.length === 0) return
    jobProc.command = jobs[0]
    jobs = jobs.slice(1)
    jobProc.running = true
  }

  // ── the "are you sure" card ─────────────────────────────────────────────────────

  function openConfirm(message, action) {
    iconDrag.reset()
    deskDrag.reset()
    tileMenu.close()
    confirmMessage = message
    confirmAction = action
    // Cancel is the default: Enter straight after opening changes nothing.
    confirmDialog.selectedIndex = 0
    confirmOpen = true
  }

  function closeConfirm(accepted) {
    var act = confirmAction
    confirmOpen = false
    confirmAction = null
    if (accepted && act) act()
    Qt.callLater(focusIconCursor)
  }

  // The menu opens under the right-clicked item with its choices built on the spot —
  // each one's `act` closes over what it needs, and the menu closes on every choice,
  // so nothing in it can go stale.
  function openMenu(label, choices, anchorItem) {
    menuLabel = label
    menuChoices = choices
    menuCursor = 0
    menuAnchor = anchorItem.mapToItem(keyCatcher, 0, anchorItem.height)
    tileMenu.open()
  }

  function iconRowName(lane) {
    return lane === "L" ? "top row" : lane === "C" ? "middle row" : "bottom row"
  }

  // The desk row on screen: the three slots each hold one, and the mode shows one of them.
  function shownDeskRow() {
    return mode === "1" ? deskRowL : mode === "2" ? deskRowC : deskRowR
  }

  function focusIconCursor() {
    if (!opened || !iconsOnly || tileMenuOpen || confirmOpen || wsEditing >= 0 || bgPicking >= 0
        || iconDrag.busy || deskDrag.busy) return
    var row = curLane === "W" ? shownDeskRow() : curLane === "L" ? rowL : curLane === "C" ? rowC : rowR
    var tile = row.itemAt(cursor)
    if (tile) tile.forceActiveFocus(Qt.OtherFocusReason)
  }

  onCursorChanged: Qt.callLater(focusIconCursor)
  onCurLaneChanged: Qt.callLater(focusIconCursor)

  // A tile's menu: the eye's hide/show and, for a spacer, the x's delete.
  function openTileMenu(lane, i, slotItem) {
    if (iconDrag.active) return
    iconDrag.reset()
    var m = modelFor(lane)
    if (i < 0 || i >= m.count) return
    var r = m.get(i)
    curLane = lane
    cursor = i
    var choices = [{ glyph: r.hid ? iconEye : iconEyeSlash, label: r.hid ? "Show" : "Hide",
                     enabled: true, act: function() { toggleHidden(lane, i) } }]
    choices.push({ glyph: "\u2190", label: "Move left", enabled: i > 0,
                   act: function() { moveItem(lane, i, i - 1) } })
    choices.push({ glyph: "\u2192", label: "Move right", enabled: i + 1 < m.count,
                   act: function() { moveItem(lane, i, i + 1) } })
    var lanes = laneOrder()
    var otherLane = lanes[0] === lane ? lanes[1] : lanes[0]
    choices.push({ glyph: lanes.indexOf(otherLane) < lanes.indexOf(lane) ? "\u2191" : "\u2193",
                   label: "Move to " + iconRowName(otherLane), enabled: true,
                   act: function() { moveAcross(lane, i, otherLane, i) } })
    if (r.wid === "omarchy.spacer")
      choices.push({ glyph: iconX, label: "Delete", enabled: true,
                     act: function() { removeSpacer(lane, i) } })
    openMenu(r.label, choices, slotItem)
  }

  // A desk chip's menu: the desk row's buttons — background, rename (where renaming
  // exists on this machine), save, and restore, which stays listed but inert without a
  // recording, as the row's dimmed button does — then moving and deleting the desk, where
  // this machine can renumber its desks (canEditDesks).
  function openDeskMenu(i, chipItem) {
    if (i < 0 || i >= lmW.count || deskDrag.active) return
    deskDrag.reset()
    var d = lmW.get(i)
    var n = d.num, name = d.name, pin = d.bgPin, hasSnap = d.hasSnap
    curLane = "W"
    cursor = i
    var choices = [{ glyph: iconImage, label: "Background", enabled: true,
                     act: function() { openBgPicker(n, name, pin) } }]
    if (canRename)
      choices.push({ glyph: iconPencil, label: "Rename", enabled: true,
                     act: function() { wsEditing = i } })
    choices.push({ glyph: iconSave, label: "Save layout", enabled: true,
                   act: function() { wsSave(n) } })
    choices.push({ glyph: iconRestore, label: "Restore layout", note: hasSnap ? "" : "no recording",
                   enabled: hasSnap, act: function() { wsRestore(n) } })
    if (canEditDesks) {
      choices.push({ glyph: "\u2190", label: "Move left", enabled: i > 0,
                     act: function() { moveDesk(i, i - 1) } })
      choices.push({ glyph: "\u2192", label: "Move right", enabled: i + 1 < lmW.count,
                     act: function() { moveDesk(i, i + 1) } })
      choices.push({ glyph: iconTrash, label: "Delete workspace", note: lmW.count > 1 ? "" : "the only one",
                     enabled: lmW.count > 1, act: function() { requestDeleteDesk(i) } })
    }
    openMenu(name, choices, chipItem)
  }

  function menuChoose(i) {
    var choice = menuChoices[i]
    if (!choice || !choice.enabled) return
    tileMenu.close()
    choice.act()
  }

  function menuMove(delta) {
    var next = menuCursor + delta
    while (next >= 0 && next < menuChoices.length && menuChoices[next].enabled === false) next += delta
    if (next >= 0 && next < menuChoices.length) menuCursor = next
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

  // "W" is the desks: the keys, the cursor and the undo history treat that row like a lane.
  function modelFor(lane) { return lane === "W" ? lmW : lane === "L" ? lmL : lane === "C" ? lmC : lmR }

  // The icon lanes visible in the current mode, left to right on screen.
  function laneOrder() {
    return mode === "1" ? ["C", "R"] : mode === "2" ? ["L", "R"] : ["L", "C"]
  }

  // Every row (icon view) or column (list view) in screen order, the desks included — the
  // order the keys walk.
  function navOrder() {
    return mode === "1" ? ["W", "C", "R"] : mode === "2" ? ["L", "W", "R"] : ["L", "C", "W"]
  }

  // Switching mode moves the strip; the icon lane that loses its column empties into
  // its neighbour so no icon is stranded in an invisible lane.
  function setMode(m) {
    if (m === mode) return
    iconDrag.reset()
    deskDrag.reset()
    change("Move the workspaces", function() {
      if (m === "1") drainLane(lmL, lmC)
      else if (m === "2") drainLane(lmC, lmL)
      else if (m === "3") drainLane(lmR, lmC)
      mode = m
      if (navOrder().indexOf(curLane) < 0) { curLane = laneOrder()[0]; cursor = 0 }
    })
  }
  // "+ spacer" (Dave, 2026-09-01): add a new spacer row to a lane — at its end, or at
  // `at` when given (the right lane's + tile sits at the lane's start) — staged like
  // any other change. Spacers are the one widget with fungible instances, so the apply
  // script mints one when the bar has fewer than the panel asks for.
  function addSpacer(lane, at) {
    var m = modelFor(lane)
    var row = { wid: "omarchy.spacer", label: prettyName("omarchy.spacer"),
                glyph: iconFor("omarchy.spacer"), hid: false, lit: true }
    change("Add spacer", function() {
      if (at === undefined) m.append(row)
      else m.insert(Math.max(0, Math.min(m.count, at)), row)
    })
  }

  // The x on a spacer row (Dave, 2026-09-01): spacers are removable outright, not
  // just parkable — a deleted one is minted back with one click on "+ spacer".
  function removeSpacer(lane, i) {
    var m = modelFor(lane)
    if (i < 0 || i >= m.count || m.get(i).wid !== "omarchy.spacer") return
    change("Delete spacer", function() {
      m.remove(i)
      spacerDeletes++
      if (curLane === lane) cursor = Math.max(0, Math.min(m.count - 1, cursor))
    })
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
  // HYPER+S snapshot directory. Which workspaces are desks: the PERSISTENT ones where the
  // config declares any (Dave's machine: 1–8, so the workout's 9 and a second screen's
  // workspace stay out, exactly as the bar's own strip leaves them out), otherwise every
  // workspace from 1 to 10 that exists (stock Omarchy, which declares none).
  //
  // Reordering and deleting desks (2026-09-19) renumbers them, and a desk's number is
  // load-bearing wherever a config routes windows or keys to it. bin/ws-renumber moves what
  // Barbarian and stock Omarchy own, and runs the machine's workspaces-renumbered hooks for
  // the rest. So a machine whose config pins desks (any persistent one) and has no such hook
  // cannot have its desks moved from here — its config would put them back at next login.
  function fillWorkspaces(wsJson, activeJson, snapText, pins, hookPresent) {
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
    var pinned = list.filter(function(w) { return w.id >= 1 && w.ispersistent === true })
    var desks = pinned.length > 0 ? pinned
      : list.filter(function(w) { return w.id >= 1 && w.id <= 10 })
    var slots = []
    for (var i = 0; i < desks.length; i++) {
      var w = desks[i]
      slots.push(w.id)
      lmW.append({ num: w.id, name: displayName(w.id, w.name), rawName: String(w.name || ""),
                   focused: w.id === active, hasSnap: snaps[w.id] === true,
                   bgPin: String(pins[w.id] || ""), windows: w.windows || 0 })
    }
    deskSlots = slots
    deskMerges = ({})
    canEditDesks = pinned.length === 0 || hookPresent === true
  }

  function displayName(n, raw) {
    raw = String(raw || "")
    return raw === "" || raw === String(n) ? "Desk " + n : raw
  }

  // ── desks: staged ───────────────────────────────────────────────────────────────

  function moveDesk(from, to) {
    if (!canEditDesks || from === to || from < 0 || to < 0 || from >= lmW.count || to >= lmW.count) return
    var name = lmW.get(from).name
    change("Move " + name, function() {
      lmW.move(from, to, 1)
      wsEditing = -1
      if (curLane === "W") cursor = to
    })
    keyCatcher.Accessible.announce(name + ", workspace " + (to + 1) + " of " + lmW.count, Accessible.Polite)
  }

  // Where a deleted desk's windows go: the desk before it in the new order, or the one after
  // it when it is the first.
  function mergeTargetFor(i) { return i > 0 ? i - 1 : i + 1 }

  // Asks first (Dave, 2026-09-19: "When deleting a workspace, it should ask if you are sure"),
  // and says where the windows will go.
  function requestDeleteDesk(i) {
    if (!canEditDesks || i < 0 || i >= lmW.count || lmW.count < 2) return
    var d = lmW.get(i), into = lmW.get(mergeTargetFor(i))
    var num = d.num
    var where = "\u201C" + into.name + "\u201D"
    openConfirm(d.windows > 0
      ? "Delete the workspace \u201C" + d.name + "\u201D? "
        + (d.windows === 1 ? "Its window" : "Its " + d.windows + " windows") + " will move to " + where + "."
      : "Delete the empty workspace \u201C" + d.name + "\u201D?",
      function() { deleteDesk(rowForWs(num)) })
  }

  function deleteDesk(i) {
    if (!canEditDesks || i < 0 || i >= lmW.count || lmW.count < 2) return
    var d = lmW.get(i), t = mergeTargetFor(i)
    var num = d.num, name = d.name, windows = d.windows
    var intoNum = lmW.get(t).num, intoWindows = lmW.get(t).windows
    change("Delete " + name, function() {
      // A desk whose windows were already coming here now goes where this one's go.
      var merges = {}
      for (var k in deskMerges) merges[k] = deskMerges[k] === num ? intoNum : deskMerges[k]
      merges[num] = intoNum
      deskMerges = merges
      lmW.setProperty(t, "windows", intoWindows + windows)
      lmW.remove(i)
      wsEditing = -1
      if (curLane === "W") cursor = Math.max(0, Math.min(lmW.count - 1, cursor))
    })
    keyCatcher.Accessible.announce(name + " deleted. Control Z undoes it.", Accessible.Polite)
  }

  // Whether apply() has desks to renumber: an order that differs from the one the panel
  // opened with, or a deleted desk.
  function desksChanged() {
    for (var k in deskMerges) return true
    for (var i = 0; i < lmW.count; i++) if (lmW.get(i).num !== deskSlots[i]) return true
    return false
  }

  // ── desks: at once ──────────────────────────────────────────────────────────────

  function wsFocus(n) {
    runJob(["hyprctl", "dispatch", 'hl.dsp.focus({ workspace = "' + n + '" })'])
  }

  // Save stashes the recording it replaces, so undo can put it back (or remove the new one
  // when there was none).
  function wsSave(n) {
    var m = rowForWs(n)
    if (m < 0) return
    var had = lmW.get(m).hasSnap, name = lmW.get(m).name
    var file = snapDir + "/ws" + n + ".json"
    var key = "snap-" + n + "-" + Date.now()
    runJob(["sh", "-c", '"$0" save "$1" "$2" && "$HOME/.config/omarchy/workspace-layout/ws-layout" snapshot "$3"',
            stashScript, file, key + "-before", String(n)])
    setHasSnap(n, true)
    record("Save layout of " + name,
      function() {
        runJob(["sh", "-c", '"$0" save "$1" "$2" && "$0" put "$3" "$1"', stashScript, file,
                key + "-after", key + "-before"])
        setHasSnap(n, had)
      },
      function() {
        runJob([stashScript, "put", key + "-after", file])
        setHasSnap(n, true)
      })
  }

  function setHasSnap(n, on) {
    var m = rowForWs(n)
    if (m >= 0) lmW.setProperty(m, "hasSnap", on)
  }

  function wsRestore(n) {
    runJob(["sh", "-c", '"$HOME/.config/omarchy/workspace-layout/ws-layout" restore "$0"', String(n)])
  }

  function wsRename(n, name) {
    name = String(name || "").trim()
    var m = rowForWs(n)
    if (name === "" || m < 0) return
    var before = lmW.get(m).rawName, shown = lmW.get(m).name
    if (name === before) return
    applyRename(n, name)
    record("Rename " + shown,
      function() { applyRename(n, before) },
      function() { applyRename(n, name) })
  }

  // An empty name gives the desk back its bare number (workspace-edit's rule).
  function applyRename(n, raw) {
    runJob(["sh", "-c", '"$HOME/.local/bin/workspace-edit" set "$0" --name "$1"', String(n), String(raw || "")])
    var m = rowForWs(n)
    if (m < 0) return
    lmW.setProperty(m, "rawName", String(raw || ""))
    lmW.setProperty(m, "name", displayName(n, raw))
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
    var m = rowForWs(n)
    var before = m >= 0 ? lmW.get(m).bgPin : ""
    var name = m >= 0 ? lmW.get(m).name : "Desk " + n
    applyPin(n, path)
    bgPicking = -1
    record("Background of " + name,
      function() { applyPin(n, before === "" ? "default" : before) },
      function() { applyPin(n, path) })
  }

  function applyPin(n, path) {
    runJob([pickScript, String(n), path])
    var m = rowForWs(n)
    if (m >= 0) lmW.setProperty(m, "bgPin", path === "default" ? "" : path)
    bgPickingPin = path === "default" ? "" : path
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
  // Undo takes the file back out of the trash and pins it to the same desks again.
  function bgRemove(path) {
    var desks = []
    for (var i = 0; i < lmW.count; i++)
      if (lmW.get(i).bgPin === path) desks.push(lmW.get(i).num)
    applyBgRemove(path)
    record("Remove a background image",
      function() { applyBgRestore(path, desks) },
      function() { applyBgRemove(path) })
  }

  function applyBgRemove(path) {
    runJob([removeScript, path])
    bgThemeList = bgThemeList.filter(function(p) { return p !== path })
    for (var i = 0; i < lmW.count; i++)
      if (lmW.get(i).bgPin === path) lmW.setProperty(i, "bgPin", "")
    if (bgPickingPin === path) bgPickingPin = ""
  }

  function applyBgRestore(path, desks) {
    runJob([restoreBgScript, path].concat(desks.map(String)))
    if (bgThemeList.indexOf(path) < 0) bgThemeList = bgThemeList.concat([path]).sort()
    for (var i = 0; i < lmW.count; i++)
      if (desks.indexOf(lmW.get(i).num) >= 0) lmW.setProperty(i, "bgPin", path)
    if (bgPicking >= 0 && desks.indexOf(bgPicking) >= 0) bgPickingPin = path
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
      var tail6 = String(tail5[1] || "").split("---HOOK---")
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
      var pl = String(tail6[0] || "").split("\n")
      for (var pi = 0; pi < pl.length; pi++) {
        var pm = pl[pi].match(/\/ws(\d+)\.[A-Za-z]+\|(.+)$/)
        if (pm) pins[parseInt(pm[1], 10)] = pm[2].trim()
      }
      fillWorkspaces(tail[0] || "[]", tail2[0] || "{}", tail3[0] || "", pins,
                     String(tail6[1] || "").trim() !== "")
    } catch (e) {
      loadError = "Could not read the bar layout file."
    }
    wsEditing = -1
    bgPicking = -1
    tileMenu.close()
    spacerDeletes = 0
    undoStack = []
    redoStack = []
    var lanes = laneOrder()
    curLane = lanes[0]
    for (var li = 0; li < lanes.length; li++)
      if (modelFor(lanes[li]).count > 0) { curLane = lanes[li]; break }
    cursor = 0
    Qt.callLater(focusIconCursor)
  }

  // Hiding also PARKS the row at its lane's far end, so a lane's hidden widgets sit
  // together instead of leaving gaps through the run (Dave, 2026-09-12): the end of the
  // queue for the left lane (and the centre one, which has no outer edge), the start of
  // it for the right lane — either way the end away from the screen edge that lane hugs.
  // Showing one again leaves it where it is, in among the hidden, until it is dragged or
  // carried out.
  function toggleHidden(lane, i) {
    if (lane === "W") return
    var m = modelFor(lane)
    if (i < 0 || i >= m.count) return
    var nowHid = !m.get(i).hid
    change((nowHid ? "Hide " : "Show ") + m.get(i).label, function() {
      m.setProperty(i, "hid", nowHid)
      // Optimistic: an un-parked widget lights up (it only actually draws after apply).
      m.setProperty(i, "lit", !nowHid)
      if (nowHid) moveItem(lane, i, lane === "R" ? 0 : m.count - 1)
    })
  }

  function moveItem(lane, from, to) {
    if (lane === "W") { moveDesk(from, to); return }
    var m = modelFor(lane)
    if (from === to || from < 0 || to < 0 || from >= m.count || to >= m.count) return
    change("Move " + m.get(from).label, function() {
      m.move(from, to, 1)
      if (curLane === lane) cursor = to
    })
    if (iconsOnly) keyCatcher.Accessible.announce(m.get(to).label + ", " + iconRowName(lane)
      + ", position " + (to + 1) + " of " + m.count, Accessible.Polite)
  }

  // A row changes lanes whole: removed from one column, inserted into the other at the
  // drop position. The cursor follows it.
  function moveAcross(fromLane, index, toLane, at) {
    if (fromLane === toLane || fromLane === "W" || toLane === "W") return
    var m1 = modelFor(fromLane), m2 = modelFor(toLane)
    if (index < 0 || index >= m1.count) return
    var r = m1.get(index)
    var row = { wid: r.wid, label: r.label, glyph: r.glyph, hid: r.hid, lit: r.lit }
    change("Move " + row.label, function() {
      m1.remove(index)
      at = Math.min(Math.max(0, at), m2.count)
      m2.insert(at, row)
      curLane = toLane
      cursor = at
    })
    if (iconsOnly) keyCatcher.Accessible.announce(row.label + ", " + iconRowName(toLane)
      + ", position " + (at + 1) + " of " + m2.count, Accessible.Polite)
  }

  function moveCursor(delta) {
    var m = modelFor(curLane)
    if (m.count === 0) return
    cursor = Math.max(0, Math.min(m.count - 1, cursor + delta))
  }

  function switchLane(dir) {
    var lanes = navOrder()
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
    if (desksChanged()) renumberDesks()
  }

  // Detached: it outlives the panel, and a bar reload from the layout write above cannot stop
  // it half way. It reports only failures, as a notification.
  function renumberDesks() {
    var argv = [renumberScript, "--order"]
    var order = []
    for (var i = 0; i < lmW.count; i++) order.push(lmW.get(i).num)
    argv.push(order.join(","))
    for (var k in deskMerges) argv.push("--delete", k + ":" + deskMerges[k])
    Quickshell.execDetached(["sh", "-c", 'exec "$0" "$@" >/dev/null 2>&1'].concat(argv))
  }

  function acceptAndClose() { close() }
  function cancelAndClose() { cancelled = true; close() }

  onOpenedChanged: {
    iconDrag.reset()
    deskDrag.reset()
    confirmOpen = false
    confirmAction = null
    gestureState = null
    changeDepth = 0
    undoNote = ""
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
        "echo ---PINS---; tn=\"$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null)\"; for f in \"$HOME/.config/omarchy/workspace-backgrounds/$tn\"/ws*.*; do [ -e \"$f\" ] && echo \"$f|$(readlink -f \"$f\")\"; done; " +
        "echo ---HOOK---; ls -A \"$HOME/.config/omarchy/hooks/workspaces-renumbered\" \"$HOME/.config/omarchy/hooks/workspaces-renumbered.d\" 2>/dev/null; true"]
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

  // The desk actions, one at a time in the order they were asked for (see runJob) — each
  // tool it calls does its own toasting, so nothing is echoed here.
  Process {
    id: jobProc
    onExited: Qt.callLater(root.nextJob)
  }

  Timer {
    id: undoNoteTimer
    interval: 3500
    onTriggered: root.undoNote = ""
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
            // Dave's second mock-editor pass (2026-09-01), retuned on 2026-09-12 so the
            // two states have room between them: this icon at 60% when the widget is
            // drawing, 55% when it is not (25% until that day). The eye and x buttons
            // keep the old 55%; headings and helper wear muted, the rules accent at 18%.
            color: root.foreground
            opacity: wrap.model.lit ? 0.6 : 0.55
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
          opacity: wrap.model.lit ? 1 : 0.55    // faded = drawing nothing right now
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
        // The row reorders live as it is dragged, so the whole drag is one undo step.
        drag.onActiveChanged: if (drag.active) root.beginGesture()
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
          var label = "Move " + wrap.model.label
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
          root.endGesture(label)
        }
        onCanceled: { card.x = 0; card.y = Style.space(2); root.endGesture("Move") }
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
        text: "Add spacer"
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

  component IconTile: Rectangle {
    required property var entry
    property bool highlighted: false
    property bool lifted: false

    radius: Style.cornerRadius
    color: lifted
      ? Qt.tint(Color.background, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18))
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, highlighted ? 0.10 : 0.04)
    border.width: lifted ? Math.max(1, Style.space(1)) : 0
    border.color: root.accent

    InkGlyph {
      anchors.fill: parent
      text: entry.wid === "omarchy.spacer" ? "" : entry.glyph || root.monogramFor(entry.label)
      font.family: root.fontFamily
      font.pixelSize: entry.glyph ? Style.font.title : Style.font.caption
      font.bold: !entry.glyph
      color: entry.hid ? root.urgent : root.foreground
      opacity: lifted ? 1 : entry.hid || !entry.lit ? 0.55 : 1
    }
  }

  component IconRow: Reordering.ReorderRow {
    id: irow

    property alias align: irow.alignment
    controller: iconDrag
    model: lane === "L" ? lmL : lane === "C" ? lmC : lmR
    width: parent.width
    maximumSlotWidth: Style.space(32)
    minimumSlotWidth: Style.space(22)
    tileInset: Style.space(2)
    tileHeight: root.tileHeight
    verticalPadding: root.rowPad
    hysteresis: Style.space(3)

    onSelected: function(index) {
      if (iconDrag.busy) return
      root.curLane = lane
      root.cursor = index
    }
    onMenuRequested: function(index, anchor) { root.openTileMenu(lane, index, anchor) }

    Rectangle {
      id: dropIndicator
      visible: irow.receiving && (iconDrag.sourceRow !== irow || iconDrag.sourceIndex !== iconDrag.targetIndex)
      x: irow.startFor(irow.previewCount) + iconDrag.targetIndex * irow.slotWidth + irow.tileInset
      y: root.rowPad + root.tileHeight + Style.space(4)
      width: irow.slotWidth - 2 * irow.tileInset
      height: Math.max(1, Style.space(2))
      radius: height / 2
      color: root.accent
      border.width: 0
      Accessible.ignored: true
    }

    delegate: IconTile {
      id: tile
      required property var model
      required property int index
      property bool ready: false
      entry: model
      x: irow.itemX(index)
      y: root.rowPad
      width: irow.slotWidth - 2 * irow.tileInset
      height: root.tileHeight
      opacity: irow.isLifted(index) ? 0 : 1
      highlighted: root.curLane === irow.lane && root.cursor === index
      Component.onCompleted: ready = true

      Behavior on x {
        enabled: tile.ready && !irow.isLifted(tile.index)
        NumberAnimation { duration: iconDrag.motionDuration; easing.type: Easing.OutCubic }
      }
      Behavior on width {
        enabled: tile.ready
        NumberAnimation { duration: iconDrag.motionDuration; easing.type: Easing.OutCubic }
      }

      Accessible.role: Accessible.Button
      Accessible.name: model.label + (model.hid ? ", hidden" : "") + ", "
        + root.iconRowName(irow.lane) + ", " + (index + 1) + " of " + irow.count
      Accessible.description: "Reorder with H and L, move between rows with J and K. Press F10 for options."
      Accessible.focusable: true
      Accessible.onPressAction: root.openTileMenu(irow.lane, index, tile)

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_F10 || event.key === Qt.Key_Menu) {
          root.openTileMenu(irow.lane, index, tile)
          event.accepted = true
        }
      }

      PanelToolTip {
        visible: irow.hoveredIndex === tile.index && !iconDrag.busy && !root.tileMenuOpen
        text: tile.model.label
        fontFamily: root.fontFamily
      }
    }

    // A labelled chip rather than a one-slot tile (Dave, 2026-09-12: "make the spacer
    // (+) say (Add spacer) instead"), sized to its words like a desk chip and parked at
    // the row's far end. It is wider than a slot, so a lane of more than about twenty
    // tiles will reach it — the tiles squeeze first, and the chip paints on top.
    Item {
      id: addTile
      z: 2
      x: irow.align === "right" ? 0
       : irow.align === "left" ? irow.width - width
       : irow.startFor(irow.previewCount) + (irow.previewCount + 1) * irow.slotWidth
      width: addChip.width + 2 * irow.tileInset
      height: irow.height

      Rectangle {
        id: addChip
        x: irow.tileInset
        y: root.rowPad
        width: addLabel.implicitWidth + Style.space(20)
        height: root.tileHeight
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                       addArea.containsMouse ? 0.10 : 0.04)

        Behavior on color { ColorAnimation { duration: 80 } }

        // Centred on the capital band, like the desk chips beside it in the middle row.
        TextMetrics {
          id: addCapBand
          font: addLabel.font
          text: "H"
        }

        Text {
          id: addLabel
          anchors.horizontalCenter: parent.horizontalCenter
          y: Math.round(addChip.height / 2 - (addLabel.baselineOffset + addCapBand.tightBoundingRect.y
                                              + addCapBand.tightBoundingRect.height / 2))
          text: "+  Add spacer"
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
        enabled: !iconDrag.busy
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addSpacer(irow.lane, irow.align === "right" ? 0 : undefined)
      }
    }
  }

  // Icon-only mode's workspaces row: the desks as chips, placed as the strip sits on
  // the bar. A click goes to the desk; a right-click opens the desk menu (background,
  // rename, save, restore, move, delete); a rename edits the chip in place. Chips drag
  // along the row to reorder the desks (2026-09-19) — the icon tiles' pick-up, make-room
  // and drop, through a controller of their own so a desk never lands among the icons.
  component DeskRow: Reordering.ReorderRow {
    id: drow

    property alias align: drow.alignment
    lane: "W"
    controller: deskDrag
    model: lmW
    width: parent.width
    variableWidths: true
    spacing: Style.space(4)
    reorderable: root.canEditDesks
    ignoredIndex: root.wsEditing
    tileHeight: root.tileHeight
    verticalPadding: root.rowPad
    hysteresis: Style.space(3)

    onSelected: function(index) {
      if (deskDrag.busy) return
      root.curLane = "W"
      root.cursor = index
    }
    onActivated: function(index) { if (index < lmW.count) root.wsFocus(lmW.get(index).num) }
    onMenuRequested: function(index, anchor) { root.openDeskMenu(index, anchor) }

    Rectangle {
      visible: drow.receiving && deskDrag.sourceIndex !== deskDrag.targetIndex
      x: drow.landingX()
      y: root.rowPad + root.tileHeight + Style.space(4)
      width: deskDrag.previewWidth
      height: Math.max(1, Style.space(2))
      radius: height / 2
      color: root.accent
      Accessible.ignored: true
    }

    delegate: Rectangle {
      id: chip
      required property var model
      required property int index
      readonly property bool editing: root.wsEditing === index
      property bool ready: false

      x: drow.itemX(index)
      y: root.rowPad
      width: editing ? Style.space(150) : chipLabel.implicitWidth + Style.space(20)
      height: root.tileHeight
      radius: Style.cornerRadius
      opacity: drow.isLifted(index) ? 0 : 1
      color: chip.model.focused
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        : (root.curLane === "W" && root.cursor === index) || drow.hoveredIndex === index
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
      Component.onCompleted: ready = true

      Behavior on color { ColorAnimation { duration: 80 } }
      Behavior on x {
        enabled: chip.ready && !drow.isLifted(chip.index)
        NumberAnimation { duration: deskDrag.motionDuration; easing.type: Easing.OutCubic }
      }

      Accessible.role: Accessible.Button
      Accessible.name: chip.model.name + ", workspace " + (index + 1) + " of " + drow.count
      Accessible.description: root.canEditDesks
        ? "Click to go there. Reorder with H and L, delete with X. Press F10 for options."
        : "Click to go there. Press F10 for options."
      Accessible.focusable: true
      Accessible.onPressAction: root.wsFocus(chip.model.num)

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_F10 || event.key === Qt.Key_Menu) {
          root.openDeskMenu(index, chip)
          event.accepted = true
        }
      }

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
    focus: root.tileMenuOpen && selected
    Keys.forwardTo: [keyCatcher]
    Accessible.role: Accessible.MenuItem
    Accessible.name: label
    Accessible.description: note
    Accessible.onPressAction: if (enabled) chosen()
    onSelectedChanged: if (selected && root.tileMenuOpen) forceActiveFocus(Qt.OtherFocusReason)

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
  // save (HYPER+S), restore (HYPER+R) and delete per desk. Reusable in whichever slot the
  // mode puts it. Rows drag up and down to reorder the desks, live like the icon columns
  // (2026-09-19); the number shown is the one the desk will have once the change is applied.
  component DeskList: ListView {
    id: dlist

    readonly property int slotHeight: Style.space(34)
    width: parent.width
    height: count * slotHeight
    clip: false
    interactive: false
    spacing: 0
    model: lmW

    move: Transition { NumberAnimation { properties: "y"; duration: 110 } }
    moveDisplaced: Transition { NumberAnimation { properties: "y"; duration: 110 } }
    displaced: Transition { NumberAnimation { properties: "y"; duration: 110 } }

    delegate: Item {
      id: wrow
      required property var model
      required property int index

      width: dlist.width
      height: dlist.slotHeight
      z: rowDrag.drag.active ? 10 : 0

      // Under the card, so the card's buttons take their own clicks: a click anywhere else
      // on the row goes to the desk, and a drag reorders the desks.
      MouseArea {
        id: rowDrag
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.wsEditing !== wrow.index
        cursorShape: !root.canEditDesks ? Qt.PointingHandCursor
          : drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: root.canEditDesks ? wcard : null
        drag.axis: Drag.YAxis

        onContainsMouseChanged: if (containsMouse) { root.curLane = "W"; root.cursor = wrow.index }
        drag.onActiveChanged: if (drag.active) root.beginGesture()
        onClicked: root.wsFocus(wrow.model.num)
        onPositionChanged: {
          if (!drag.active) return
          var centerY = wcard.mapToItem(dlist.contentItem, 0, wcard.height / 2).y
          var to = Math.max(0, Math.min(dlist.count - 1, Math.floor(centerY / dlist.slotHeight)))
          if (to !== wrow.index) root.moveDesk(wrow.index, to)
        }
        onReleased: {
          var label = "Move " + wrow.model.name
          wcard.x = 0; wcard.y = Style.space(2)
          root.endGesture(label)
        }
        onCanceled: { wcard.x = 0; wcard.y = Style.space(2); root.endGesture("Move") }
      }

      Rectangle {
        id: wcard
        width: wrow.width
        // Fixed row height, NOT wrow.height - the delegate grows to hold the open
        // background picker, and a card bound to it ballooned over the rows below
        // (Dave's "jumbled" screenshot, 2026-09-01).
        height: Style.space(30)
        y: Style.space(2)
        radius: Style.cornerRadius
        color: rowDrag.drag.active
          ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          : wrow.model.focused
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            : (root.curLane === "W" && root.cursor === wrow.index) || rowDrag.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

        Text {
          id: wnum
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: String(root.deskSlots[wrow.index] !== undefined ? root.deskSlots[wrow.index] : wrow.model.num)
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
          onVisibleChanged: if (visible && wrow.model && wrow.model.name !== undefined) { text = wrow.model.name; forceActiveFocus(); selectAll() }
          onAccepted: { root.wsRename(wrow.model.num, text); root.wsEditing = -1 }
          Keys.onEscapePressed: root.wsEditing = -1
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
          onClicked: root.openBgPicker(wrow.model.num, wrow.model.name, wrow.model.bgPin)
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
          // Same rule as the pencil: no delete on this machine, no gap for it.
          anchors.right: root.canEditDesks ? wtrash.left : parent.right
          anchors.rightMargin: root.canEditDesks ? 0 : Style.space(2)
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

        // Last in the row, apart from the everyday buttons; it asks before anything happens.
        PanelActionButton {
          id: wtrash
          visible: root.canEditDesks
          anchors.right: parent.right
          anchors.rightMargin: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.iconTrash
          tooltipText: dlist.count > 1 ? "Delete workspace" : "The only workspace cannot be deleted"
          foreground: Qt.darker(root.foreground, 1.8)
          hoverColor: root.urgent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          opacity: dlist.count > 1 ? 1 : 0.3
          onClicked: root.requestDeleteDesk(wrow.index)
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
      // While the "are you sure" card is up it takes the keys: Escape cancels, Enter takes
      // the button that is lit, and h/l, the arrows and Tab move between the two buttons.
      onCloseRequested: {
        if (root.confirmOpen) root.closeConfirm(false)
        else if (iconDrag.active) iconDrag.cancel()
        else if (deskDrag.active) deskDrag.cancel()
        else if (root.tileMenuOpen) tileMenu.close()
        else if (root.bgPicking >= 0) root.bgPicking = -1
        else root.cancelAndClose()
      }
      onActivateRequested: {
        if (root.confirmOpen) { root.closeConfirm(confirmDialog.selectedIndex === 1); return }
        if (iconDrag.busy || deskDrag.busy) return
        if (root.tileMenuOpen) root.menuChoose(root.menuCursor)
        else if (root.bgPicking >= 0) root.bgPicking = -1
        else root.acceptAndClose()
      }
      onTabRequested: function(direction) {
        if (root.confirmOpen) confirmDialog.selectedIndex = 1 - confirmDialog.selectedIndex
      }
      // x (PanelKeyCatcher's delete key) hides/shows the selected row — or, on a desk,
      // asks to delete it.
      onDeleteRequested: {
        if (root.confirmOpen || root.bgPicking >= 0 || root.tileMenuOpen || iconDrag.busy || deskDrag.busy) return
        if (root.curLane === "W") root.requestDeleteDesk(root.cursor)
        else root.toggleHidden(root.curLane, root.cursor)
      }
      // j/k (dy) walk a column, h/l (dx) hop between the two. In icon-only mode the
      // keys follow the layout: h/l walk the row, j/k hop between rows. In the tile
      // menu, j/k walk its choices.
      onMoveRequested: function(dx, dy) {
        if (root.confirmOpen) { if (dx !== 0) confirmDialog.selectedIndex = dx > 0 ? 1 : 0; return }
        if (iconDrag.busy || deskDrag.busy) return
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
        if (root.confirmOpen || iconDrag.busy || deskDrag.busy) return
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

      // Ctrl+Z / Ctrl+Shift+Z (or Ctrl+Y). While a desk is being renamed the text field
      // keeps them for its own text.
      Shortcut {
        sequences: ["Ctrl+Z"]
        enabled: root.opened && !root.confirmOpen && root.wsEditing < 0
        onActivated: root.undo()
      }
      Shortcut {
        sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]
        enabled: root.opened && !root.confirmOpen && root.wsEditing < 0
        onActivated: root.redo()
      }

      Reordering.ReorderController {
        id: iconDrag
        anchors.fill: parent
        z: 10
        enabled: root.opened && root.iconsOnly && root.bgPicking < 0 && !root.confirmOpen
        rows: [rowL, rowC, rowR]
        motionDuration: root.setting("reduce-motion", false) ? 0 : 160
        onDropped: function(fromRow, fromIndex, toRow, toIndex) {
          if (fromRow === toRow) root.moveItem(fromRow.lane, fromIndex, toIndex)
          else root.moveAcross(fromRow.lane, fromIndex, toRow.lane, toIndex)
        }
        onDragCancelled: keyCatcher.Accessible.announce("Drag cancelled", Accessible.Polite)
        onBusyChanged: if (!busy) Qt.callLater(root.focusIconCursor)

        IconTile {
          entry: iconDrag.entry
          visible: iconDrag.busy
          x: iconDrag.previewX
          y: iconDrag.previewY
          width: iconDrag.previewWidth
          height: iconDrag.previewHeight
          lifted: true
          Accessible.ignored: true
        }
      }

      // The desk chips' own drag: rows holds the three desk rows (the mode shows one), so a
      // desk can only land among the desks.
      Reordering.ReorderController {
        id: deskDrag
        anchors.fill: parent
        z: 10
        enabled: root.opened && root.iconsOnly && root.bgPicking < 0 && !root.confirmOpen
        rows: [deskRowL, deskRowC, deskRowR]
        motionDuration: iconDrag.motionDuration
        onDropped: function(fromRow, fromIndex, toRow, toIndex) { root.moveDesk(fromIndex, toIndex) }
        onDragCancelled: keyCatcher.Accessible.announce("Drag cancelled", Accessible.Polite)
        onBusyChanged: if (!busy) Qt.callLater(root.focusIconCursor)

        // The lifted chip: the tile's lifted look, with the desk's name.
        Rectangle {
          visible: deskDrag.busy
          x: deskDrag.previewX
          y: deskDrag.previewY
          width: deskDrag.previewWidth
          height: deskDrag.previewHeight
          radius: Style.cornerRadius
          color: Qt.tint(Color.background, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18))
          border.width: Math.max(1, Style.space(1))
          border.color: root.accent
          Accessible.ignored: true

          TextMetrics {
            id: liftedCapBand
            font: liftedLabel.font
            text: "H"
          }

          Text {
            id: liftedLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height / 2 - (liftedLabel.baselineOffset + liftedCapBand.tightBoundingRect.y
                                               + liftedCapBand.tightBoundingRect.height / 2))
            text: deskDrag.entry.name || ""
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.foreground
          }
        }
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
            color: root.urgent
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
        // the bar, a rule between them. The shared overlay carries a dragged tile.
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

            IconRow {
              id: rowL
              lane: "L"
              align: "left"
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode !== "1"
            }

            DeskRow {
              id: deskRowL
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

            IconRow {
              id: rowC
              lane: "C"
              align: "center"
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode !== "2"
            }

            DeskRow {
              id: deskRowC
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

            IconRow {
              id: rowR
              lane: "R"
              align: "right"
              anchors.verticalCenter: parent.verticalCenter
              visible: root.mode !== "3"
            }

            DeskRow {
              id: deskRowR
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
          id: idleIconHelp
          visible: false
          width: parent.width
          topPadding: Style.space(10)
          text: "Drag to rearrange  ·  Right-click or F10 for options  ·  H/L reorder, J/K move between rows\nClick a desk to go there  ·  Ctrl+Z undoes  ·  Enter applies  ·  Esc discards changes"
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          font: arrangementHelp.font
          Accessible.ignored: true
        }

        Text {
          id: arrangementHelp
          visible: root.bgPicking < 0
          width: parent.width
          height: root.iconsOnly ? idleIconHelp.implicitHeight : implicitHeight
          // Breathing room above, centred under the three columns (Dave, 2026-09-01).
          topPadding: Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          text: root.undoNote !== ""
            ? root.undoNote + "  ·  Ctrl+Z undoes, Ctrl+Shift+Z redoes"
            : root.iconsOnly
              ? iconDrag.active || deskDrag.active
                ? "Release to place  ·  Esc cancels this drag"
                : idleIconHelp.text
              : "drag rows, across too  ·  eye / x hides  ·  desks: click goes there,  saves,  restores  ·  Ctrl+Z undoes  ·  Enter applies"
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.iconsOnly ? root.foreground : root.muted
        }
      }

      // The "are you sure" card before a desk is deleted — the shell's own, as the menu's
      // uninstall and the clipboard's clear use it — over the whole panel. Its keys are
      // routed from the key catcher's handlers above.
      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 20
        opened: root.confirmOpen
        message: root.confirmMessage
        cancelText: "Cancel"
        confirmText: "Delete"
        foreground: root.foreground
        selectedText: root.accent
        fontFamily: root.fontFamily
        onCanceled: root.closeConfirm(false)
        onConfirmed: root.closeConfirm(true)
      }

      // The tile menu: the name, then the choices the eye and x offer in list mode. A
      // The menu keeps focus on its selected action and forwards navigation to the
      // panel key dispatcher. A press outside closes it and restores tile focus.
      Popup {
        id: tileMenu
        x: Math.max(0, Math.min(root.menuAnchor.x, keyCatcher.width - width))
        y: Math.max(0, Math.min(root.menuAnchor.y, keyCatcher.height - height))
        width: Style.space(220)
        padding: Style.space(4)
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnPressOutside
        onOpenedChanged: {
          root.tileMenuOpen = opened
          if (opened) {
            var choice = menuItems.itemAt(root.menuCursor)
            if (choice) choice.forceActiveFocus(Qt.OtherFocusReason)
          } else Qt.callLater(root.focusIconCursor)
        }

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
            color: root.foreground
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
          }

          Item { width: 1; height: Style.space(3) }

          Repeater {
            id: menuItems
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
