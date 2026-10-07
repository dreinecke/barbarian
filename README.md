# Barbarian

Barbarian is a panel for the [Omarchy](https://omarchy.org) Quickshell bar: open it
with a keybind and reorder, re-lane or hide every widget on the bar's right side by
dragging (or with `j`/`k` + `J`/`K`), add, reorder and delete workspaces (desks), and give
each desk its own wallpaper. `Ctrl+Z` undoes any change made while the panel is open,
and `Ctrl+Shift+Z` (or `Ctrl+Y`) redoes it.

Since 2026-10-07 it is also the home of **Reptile**, its former sibling plugin: the
desk-layouts panel opened with `HYPER+L`, where every desk's recording is drawn as
blocks — drag to swap, drag the line to resize, `×` removes, `+` adds, saved as you
go — plus the quick-apps tab that gives an app a key of its own. One plugin, one
installer, one id: the keybind is now
`omarchy-shell tinkerbell.arrange layouts` (the old `tinkerbell.reptile` target is
migrated away by `install.sh`, which also prints the keybind reminder while
`~/.config/hypr/bindings.lua` still names the old id). Reptile's commit history was
grafted in — `git log --follow plugin/Reptile.qml`.

The grid button beside the tick and cross switches to **icon-only mode**: three rows
in the bar's own order, each placed as it sits on the bar — the left lane's glyphs at
the left edge, the workspaces as chips in the middle, the right lane's glyphs at the
right edge — and no names. Drag a tile along its row to reorder, onto another row to
change lanes. The tile follows the grab point while its neighbors make room; a short line
marks a new landing position. Releasing commits the move. Escape during a drag, losing
the pointer grab, or dropping outside the icon rows cancels just that move, preserving
earlier staged changes. Hover for the name; right-click or press `F10` for the menu that
moves, hides or shows it
(and deletes a spacer). A widget that is an installed plugin — a folder with a manifest under
`~/.config/omarchy/plugins` — also offers **Uninstall**: it asks first, stages the tile's
departure like every other change (`Ctrl+Z` undoes it, Escape forgets it), and on apply the
entry leaves `shell.json` while `plugin/bin/plugin-uninstall` puts the plugin's folder in the
trash — one folder at a time, with the shell's restart riding along on the installer's next
run. A widget parked off the bar wears the theme's urgent colour,
and hiding one sends it to its lane's far end so the hidden ones sit together. Click a desk chip to go there; right-click it for background,
rename, save, restore, move and delete; drag it along its row to reorder the desks. The keys
follow the layout — `h`/`l` walk a row, `j`/`k` hop rows (the desks' row included), `H`/`L`
carry, `J`/`K` throw, `x` hides a widget or deletes a desk. The choice is remembered in
`~/.local/state/omarchy/barbarian.json`.

## Adding, reordering and deleting desks

**+ Add workspace** sits at the far end of the desks' row in icon view (the right end, or the left
when the workspaces sit on the right of the bar) and at the foot of the desks column in the list.
It puts a new desk at the end and opens its name for typing; Enter takes the name and, as with
any rename, applies the panel's changes and closes it, while Escape leaves it called "New
workspace" (made with no name, it shows its bare number). Until then the new desk can be renamed,
moved and removed (without the "are you sure", since nothing is on it), but has no background,
recording or desk to go to. New desks take numbers no other workspace has, up to 10, and the
button dims when there is none left.

Drag a desk (either view), carry it with the keys, or use its menu; delete one from its menu
(icon view) or its bin button (list view). Deleting asks first, and says where the desk's
windows go: the desk before it, or the one after it when it is the first (never a new desk).
All three are staged with the rest of the panel's changes, so Escape still throws them away.

Applying renumbers the desks so the Nth desk on the bar is desk N again, and `SUPER+N` still
reaches it. `plugin/bin/ws-renumber` does it in one pass after the panel closes:

- each desk is given its new number in place (Hyprland's `workspace.change_id`), so its windows
  and their tiling stay exactly as they were;
- wallpaper pins move with their desk in every theme, an Auto desk keeps its picture, and stock
  Omarchy's per-desk tiling layout (`SUPER+L`) moves with it too;
- every executable in `~/.config/omarchy/hooks/workspaces-renumbered.d/` runs first, with one
  `move:OLD:NEW` or `delete:OLD:NEW` argument per changed desk (for a deleted desk, `NEW` is the
  desk its windows went to) and one `add:NEW:NAME` per new desk (`add:NEW` when it has no name).
  That is where a machine's own config — the desk table, window rules that name a desk by
  number, scripts that open things on a desk — follows along. A hook that exits non-zero stops
  the whole pass with nothing changed;
- a new desk is made last, once the others have their numbers: by the config reload, where a
  hook wrote it into the config, or otherwise as a persistent workspace that lasts until
  Hyprland next reloads its config (with nowhere to write it down, an empty desk cannot outlive
  that).

Which workspaces are desks: the persistent ones when the Hyprland config declares any, otherwise
every workspace from 1 to 10 that exists. A config that declares persistent desks would put them
back at the next login, so on such a machine Barbarian offers adding, reordering and deleting only
once a `workspaces-renumbered` hook is installed. A failure is reported as a notification, and the last
passes are logged in `~/.local/state/omarchy/barbarian-renumber.log`.

The drag preview is independent of the lane layout: pointer movement never reorders the
model. Neighbors and the landing animate over 160 ms; the held tile has no easing or
lag. Set `"reduce-motion": true` on the `tinkerbell.arrange` entry in `shell.json` to
disable these animations. Qt does not currently expose an OS reduced-motion preference.

It was built by a Claude Code agent on the author's machine, extracted from the
machine-configuration repo it grew up in (51 commits of history carried over).

## Themes

The palette button beside the view toggle, or `t`, closes the panel and opens a full-screen grid
of every theme Omarchy can see, in the look of
[omarchy-theme-manager's grid](https://github.com/mtolhuys/omarchy-theme-manager): Installed,
Omarchy defaults, Hidden and Broken links, each a row of previews. It is also reachable without
the panel: `omarchy-shell shell toggle tinkerbell.arrange '{}'` (bind it to a key). The button is
dimmed while the panel has changes waiting; apply or cancel them first, because applying rewrites
`shell.json` and the shell rebuilds its overlays when that file changes.

Arrow keys move, typing filters, and Delete acts on the selected theme; so does the × that hovering
a theme shows in its top-right corner. A remove or a hide always asks first, and Cancel is the
default for a remove. Every change is made on the spot, so Enter, which applies and closes the
panel, closes the grid, and so does Esc.

- **Your own themes** (folders in `~/.config/omarchy/themes`) go to the trash, so they can come
  back. A link is unlinked and whatever it points to is left alone. Your copy of one of Omarchy's
  themes can be removed too; Omarchy's original stays.
- **Omarchy's own themes** can only be hidden. The `omarchy` package owns them, so deleting one
  needs root and the next update would put it back. Hiding takes the theme out of Omarchy's own
  theme picker as well as this grid; Restore puts it back. The list lives in
  `~/.local/state/omarchy/barbarian-hidden-themes`.
- **Broken links** — links whose target is gone — can be removed one at a time, or all at once
  with Shift+Delete.
- **The theme in use** cannot be removed or hidden.

Omarchy rebuilds its picker's cache whenever a theme folder changes, which brings hidden themes
back; the grid puts them away again within about 15 seconds. The first picker open after installing
a theme some other way, or after an Omarchy update, can still show a hidden theme once.
`plugin/bin/theme-remover` does every change on disk, and its header explains the two caches it
keeps in line.

## What's inside

- **`plugin/`** — the Quickshell bar widget (`tinkerbell.arrange`) and, as the same plugin's
  overlay entry point, the theme grid (`ThemeRemover.qml` and the `Theme*.qml` beside it). It draws nothing
  on the bar (zero width); it exists to host the panel and its IPC target, toggled
  with `qs -p /usr/share/omarchy/shell ipc call tinkerbell.arrange toggle`.
  `Reptile.qml`, instantiated by `Panel.qml`, is the merged-in layouts panel (HYPER+L,
  via `ipc call tinkerbell.arrange layouts`): its own window, header and keyboard
  model, riding the same IPC target.
  On close it writes the new order straight into Omarchy's `shell.json` (whole
  entries move, so each widget's per-widget settings travel with it) and parks
  hidden widget ids in `~/.config/omarchy/bar-hidden.json`.
  Its `bin/` scripts drive the per-desk wallpaper picker: pin any image (or a solid
  colour) to a desk, add images from Pictures/Downloads, remove ones you added, and
  hide the theme's own (listed per theme in `workspace-backgrounds/<theme>/hidden-images`).
  `bin/plugin-uninstall` is the folder half of an uninstall: once the entries have left
  `shell.json`, it trashes the plugins one at a time, each settle apart, and never restarts
  the shell itself — a restart racing the reload crashed the shell once, four racing left
  four bars, so the restart rides with the installer's next run instead. It waits out any
  desk renumber and refuses while the screen is locked (a write under `plugins/` reloads
  the whole shell — see `install.sh`).
- **`engine/`** — `per-workspace-wallpaper.sh` is the wallpaper watcher that applies those
  pins on every workspace switch and theme change. `ws-layout` and `quick-app` came with
  Reptile: recordings and restores for desk layouts, and the quick-apps engine. They
  install to `~/.config/omarchy/workspace-layout/`, where they have always lived, and the
  installer compiles them before writing (a broken engine never installs).

## Requirements

- Omarchy (built against its Quattro-era shell: the QML imports `qs.Commons` and
  `qs.Ui`, which only exist inside the Omarchy shell)
- ImageMagick (`magick`) for solid-colour wallpapers
- `jq` and `gio` (both in a standard Omarchy install) for the theme grid — `gio trash` is what
  makes a removed theme recoverable
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
renumbering, reloading, renaming, and the panel's keys and drags — runs against a second
Hyprland nested on a hidden workspace, never the session in use: `tests/nested/nested` starts
it, puts the panel on it with a throwaway HOME, types and points into it, and screenshots it
(its header lists the steps).

## License

MIT — see [LICENSE](./LICENSE).
