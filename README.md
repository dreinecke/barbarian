# Barbarian

Barbarian is a panel for the [Omarchy](https://omarchy.org) Quickshell bar: open it
with a keybind and reorder, re-lane or hide every widget on the bar's right side by
dragging (or with `j`/`k` + `J`/`K`), reorder and delete workspaces (desks), and give
each desk its own wallpaper. `Ctrl+Z` undoes any change made while the panel is open,
and `Ctrl+Shift+Z` (or `Ctrl+Y`) redoes it.

The grid button beside the tick and cross switches to **icon-only mode**: three rows
in the bar's own order, each placed as it sits on the bar — the left lane's glyphs at
the left edge, the workspaces as chips in the middle, the right lane's glyphs at the
right edge — and no names. Drag a tile along its row to reorder, onto another row to
change lanes. The tile follows the grab point while its neighbors make room; a short line
marks a new landing position. Releasing commits the move. Escape during a drag, losing
the pointer grab, or dropping outside the icon rows cancels just that move, preserving
earlier staged changes. Hover for the name; right-click or press `F10` for the menu that
moves, hides or shows it
(and deletes a spacer). A widget parked off the bar wears the theme's urgent colour,
and hiding one sends it to its lane's far end so the hidden ones sit together. Click a desk chip to go there; right-click it for background,
rename, save, restore, move and delete; drag it along its row to reorder the desks. The keys
follow the layout — `h`/`l` walk a row, `j`/`k` hop rows (the desks' row included), `H`/`L`
carry, `J`/`K` throw, `x` hides a widget or deletes a desk. The choice is remembered in
`~/.local/state/omarchy/barbarian.json`.

## Reordering and deleting desks

Drag a desk (either view), carry it with the keys, or use its menu; delete one from its menu
(icon view) or its bin button (list view). Deleting asks first, and says where the desk's
windows go: the desk before it, or the one after it when it is the first. Both are staged with
the rest of the panel's changes, so Escape still throws them away.

Applying renumbers the desks so the Nth desk on the bar is desk N again, and `SUPER+N` still
reaches it. `plugin/bin/ws-renumber` does it in one pass after the panel closes:

- each desk is given its new number in place (Hyprland's `workspace.change_id`), so its windows
  and their tiling stay exactly as they were;
- wallpaper pins move with their desk in every theme, an Auto desk keeps its picture, and stock
  Omarchy's per-desk tiling layout (`SUPER+L`) moves with it too;
- every executable in `~/.config/omarchy/hooks/workspaces-renumbered.d/` runs first, with one
  `move:OLD:NEW` or `delete:OLD:NEW` argument per changed desk (for a deleted desk, `NEW` is the
  desk its windows went to). That is where a machine's own config — window rules that name a desk
  by number, scripts that open things on a desk — follows along. A hook that exits non-zero
  stops the whole pass with nothing changed.

Which workspaces are desks: the persistent ones when the Hyprland config declares any, otherwise
every workspace from 1 to 10 that exists. A config that declares persistent desks would put them
back at the next login, so on such a machine Barbarian offers reordering and deleting only once a
`workspaces-renumbered` hook is installed. A failure is reported as a notification, and the last
passes are logged in `~/.local/state/omarchy/barbarian-renumber.log`.

The drag preview is independent of the lane layout: pointer movement never reorders the
model. Neighbors and the landing animate over 160 ms; the held tile has no easing or
lag. Set `"reduce-motion": true` on the `tinkerbell.arrange` entry in `shell.json` to
disable these animations. Qt does not currently expose an OS reduced-motion preference.

It was built by a Claude Code agent on the author's machine, extracted from the
machine-configuration repo it grew up in (51 commits of history carried over).

## What's inside

- **`plugin/`** — the Quickshell bar widget (`tinkerbell.arrange`). It draws nothing
  on the bar (zero width); it exists to host the panel and its IPC target, toggled
  with `qs -p /usr/share/omarchy/shell ipc call tinkerbell.arrange toggle`.
  On close it writes the new order straight into Omarchy's `shell.json` (whole
  entries move, so each widget's per-widget settings travel with it) and parks
  hidden widget ids in `~/.config/omarchy/bar-hidden.json`.
  Its `bin/` scripts drive the per-desk wallpaper picker: pin any image (or a solid
  colour) to a desk, add images from Pictures/Downloads, remove ones you added.
- **`engine/per-workspace-wallpaper.sh`** — the wallpaper watcher that applies those
  pins on every workspace switch and theme change. The panel's scripts call it after
  each pick; on the author's machine a user service keeps it running.

## Requirements

- Omarchy (built against its Quattro-era shell: the QML imports `qs.Commons` and
  `qs.Ui`, which only exist inside the Omarchy shell)
- ImageMagick (`magick`) for solid-colour wallpapers
- The plugin must be **listed in `shell.json`'s right section** to load at all —
  Omarchy keeps that file machine-local, so add the id by hand after installing.

## Install

```sh
git clone https://github.com/dreinecke/barbarian
cd barbarian && ./install.sh
```

Installs user-space only: the plugin to
`~/.config/omarchy/plugins/tinkerbell.arrange/`, the engine to
`~/.config/omarchy/workspace-backgrounds/`. Idempotent — re-running is the repair.
The plugin id stays `tinkerbell.arrange` for history's sake; it is load-bearing in
`shell.json`, keybinds and the engine, so it was left alone through the extraction.

After installing changed plugin code, run `omarchy restart shell` while the session is
unlocked. The shell's widget reload can reuse the QML engine's cached code; a full shell
restart is required to load edits reliably. The installer defers writes while locked.

## Verify drag behavior

The native Qt Quick tests exercise the actual pointer handler, animated displacement,
drop geometry, cancellation, and same-row and cross-row model commits — for the icon tiles
and the desk chips — without changing the running bar:

```sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests -o -,txt
python3 tests/test_ws_renumber.py
```

The second covers the desk renumbering's arithmetic and the files it moves. Its live half —
renumbering, reloading, renaming — was checked against a second Hyprland running nested on a
hidden workspace, never the session in use.

## License

MIT — see [LICENSE](./LICENSE).
