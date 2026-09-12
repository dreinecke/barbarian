# Barbarian

Barbarian is a panel for the [Omarchy](https://omarchy.org) Quickshell bar: open it
with a keybind and reorder, re-lane or hide every widget on the bar's right side by
dragging (or with `j`/`k` + `J`/`K`), and give each desk its own wallpaper.

The grid button beside the tick and cross switches to **icon-only mode**: three rows
in the bar's own order, each placed as it sits on the bar — the left lane's glyphs at
the left edge, the workspaces as chips in the middle, the right lane's glyphs at the
right edge — and no names. Drag a tile along its row to reorder, onto another row to
change lanes; hover for the name; right-click for the menu that hides or shows it
(and deletes a spacer). Click a desk chip to go there; right-click it for background,
rename, save and restore. The keys follow the layout — `h`/`l` walk a row, `j`/`k`
hop rows, `H`/`L` carry, `J`/`K` throw. The choice is remembered in
`~/.local/state/omarchy/barbarian.json`.

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

## License

MIT — see [LICENSE](./LICENSE).
