#!/bin/bash
# per-workspace-wallpaper.sh — a different wallpaper on each named workspace.
#
# ⚠️ REBUILT FOR QUATTRO, 2026-08-09. The original (T78/T83) drove **swaybg** directly — `pkill` +
# relaunch with `-c #RRGGBB` or `-i <path>` — and rewrote the per-workspace waybar tint on the way.
# Quattro retired swaybg AND waybar, so both halves of that script died at once. `git show
# 3ebc40c9:omarchy/workspace-backgrounds/per-workspace-wallpaper.sh` is the old one.
#
# The replacement is better, not just different: Quickshell owns the background and exposes it over
# IPC (`omarchy-shell background set|setInstant|transition|refresh`), so there is no process to kill,
# no flicker, and a real cross-fade available for free.
#
# ⚠️ IT PICKS FROM THE CURRENT THEME BY DEFAULT, AND THAT IS THE POINT. Omarchy themes ship several
# backgrounds; workspace N takes the Nth of them. Change theme and all six follow, with no
# per-workspace config to re-point — which is exactly what broke repeatedly on the old one, where a
# theme change or an `omarchy update` silently reset the named workspaces back to the theme image.
#
# To pin a specific image to a workspace, drop a file next to this script named `ws<N>.<ext>`
# (e.g. `ws4.png`). That is the strongest of the three rules — nothing else can override it.
#
# To fill every workspace that has NO image of its own, drop `all.<ext>` next to this script. It
# stands in for the theme's list, not for the per-workspace files. `all.png` is currently a plain
# black image, on David's instruction of 2026-08-10 ("make all backgrounds just a plain black image
# for the time being") — deleting that one file is the whole revert.
#
# ⚠️ THE ORDER OF THOSE TWO WAS THE OTHER WAY ROUND UNTIL 2026-08-11, and it read as a broken
# feature: Dave dropped `ws3.png` in and nothing happened, because `all.png` was still winning. A
# blanket image is a mood he sets once; a per-workspace image is a deliberate choice about one
# desk, so the deliberate one has to win or adding a picture looks like it did not work.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current"
# `set` cross-fades, `setInstant` swaps immediately. Instant is the default because a fade on every
# workspace switch reads as lag when you are moving between them quickly.
METHOD="${WALLPAPER_METHOD:-setInstant}"

# Headless-safe: launched outside a graphical Hyprland session (self-heal, a systemd start before the
# session is fully up), derive the runtime env the socket path needs — otherwise the bare
# ${HYPRLAND_INSTANCE_SIGNATURE} expansion crashes under `set -u`.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
    [ -S "$sock" ] && export WAYLAND_DISPLAY="$(basename "$sock")" && break
  done
fi
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || \
  export HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"

# The theme's backgrounds, sorted — Omarchy names them `0-…`, `1-…`, so sort order IS the intended
# order. Re-read on every lookup rather than cached at start: a theme change must take effect without
# restarting the watcher.
theme_backgrounds() {
  local dir
  dir="$(readlink -f "$STATE/theme" 2>/dev/null)/backgrounds"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort
}

# Which image workspace N should show. An explicit ws<N>.<ext> beats everything; failing that
# `all.<ext>` covers whatever is left; otherwise index into the theme's list, wrapping if the theme
# ships fewer images than there are workspaces.
wallpaper_for() {
  local ws="$1" override
  # A picture chosen for ONE desk is the most deliberate thing anyone can say here, so it wins.
  # ⚠️ The name must be exactly `ws<N>.<ext>` — `ws2-blue.png` does NOT match `ws2.*`. Two files
  # named that way sat in the folder doing nothing from June until Dave deleted them on 11 Aug.
  for override in "$HERE/ws$ws".*; do
    [ -f "$override" ] && { printf '%s' "$override"; return 0; }
  done
  # ⚠️ ONE FILE FILLS EVERY REMAINING WORKSPACE, and that is the point. "The rest all the same" is a
  # thing David asks for as a mood rather than a setting, so it has to be one file to add and one
  # file to delete — not an edit here, which would be a change he cannot make or undo himself.
  for override in "$HERE"/all.*; do
    [ -f "$override" ] && { printf '%s' "$override"; return 0; }
  done

  local -a list
  mapfile -t list < <(theme_backgrounds)
  [ "${#list[@]}" -gt 0 ] || return 0
  printf '%s' "${list[$(( (ws - 1) % ${#list[@]} ))]}"
}

# ---- the active-window border, matched to the bar --------------------------------------------
# Dave, 2026-08-11: "can one make that highlight match the bar color so each ws looks cohesive?"
#
# ⚠️ THE PALETTE IS READ OUT OF THE BAR PLUGIN, NOT COPIED HERE. Two lists of six colours would
# disagree the first time one of them changed, and this project has already paid for a half-done
# rename once. The plugin's `tints` map is plain enough to grep, and it stays the single place a
# workspace's colour is decided.
PLUGIN_QML="$HOME/.config/omarchy/plugins/tinkerbell.workspaces/Widget.qml"
THEME_BORDER=""

tint_for() { # <ws-id> → RRGGBB, or empty when that workspace has no colour of its own
  [ -f "$PLUGIN_QML" ] || return 0
  sed -n "s/^[[:space:]]*$1:[[:space:]]*\"#\([0-9A-Fa-f]\{6\}\)\".*/\1/p" "$PLUGIN_QML" | head -1
}

apply_border() { # <ws-id>
  local hex
  hex="$(tint_for "$1")"
  # Remember the theme's own colour once, so an unnamed workspace can be handed it back rather than
  # keeping whichever workspace was last visited.
  if [ -z "$THEME_BORDER" ]; then
    THEME_BORDER="$(hyprctl getoption general:col.active_border 2>/dev/null |
      sed -n 's/.*gradient data:[[:space:]]*\([0-9a-fA-F]\{8\}\).*/\1/p' | head -1)"
  fi
  # ⚠️ `hyprctl keyword` IS DEAD ON QUATTRO — it answers "keyword can't work with non-legacy parsers.
  # Use eval." and changes nothing, which reads exactly like a colour that refused to take. The Lua
  # equivalent is `hyprctl eval hl.config({...})`, and the option's name is a KEY IN A TABLE
  # (`["col.active_border"]`) because it has a dot in it.
  #
  # ⚠️ Hyprland REPORTS AARRGGBB and ACCEPTS RRGGBBAA. Handing back exactly what `getoption` printed
  # would put the alpha in the red channel, so the theme's own value is rotated before it goes back.
  local value=""
  if [ -n "$hex" ]; then
    value="rgba(${hex}ff)"
  elif [ -n "$THEME_BORDER" ]; then
    value="rgba(${THEME_BORDER:2}${THEME_BORDER:0:2})"
  fi
  [ -n "$value" ] || return 0
  hyprctl eval "hl.config({ general = { [\"col.active_border\"] = \"$value\" } })" >/dev/null 2>&1
}

LAST=""
apply() {
  local ws="$1" want
  # ⚠️ THE v2 EVENT IS `ID,NAME` AND ONLY THE ID IS WANTED. Passed through whole, the id lands in an
  # arithmetic expression as `2,Webscape` — bash reads the comma as the sequence operator, evaluates
  # `Webscape` as a variable name, and dies on `set -u`. Strip at the first comma.
  ws="${ws%%,*}"
  case "$ws" in ''|*[!0-9]*) return 0 ;; esac
  apply_border "$ws"
  want="$(wallpaper_for "$ws")" || return 0
  [ -n "$want" ] || return 0
  # ⚠️ DE-DUPE OR IT REPAINTS ON EVERY SWITCH. Two workspaces can resolve to the same image (a theme
  # with fewer backgrounds than workspaces wraps), and re-setting the same path is a visible flicker
  # for no change.
  #
  # ⚠️ COMPARE AGAINST THE SYMLINK, NOT A REMEMBERED LAST VALUE. A remembered value says what THIS
  # script last set; the link says what is actually on screen, and the two part company the moment
  # anything else writes it — `omarchy theme set`, `omarchy theme bg next`. With one image for every
  # workspace (the `all.<ext>` rule above) a remembered value would match forever, so the wallpaper
  # would stay on whatever the theme change left behind and never come back.
  [ "$want" = "$(readlink -f "$STATE/background" 2>/dev/null)" ] && return 0

  # ⚠️ THE SYMLINK IS THE STATE. THE IPC CALL ALONE IS THROWN AWAY WITHIN 100ms — and that is the
  # bug Dave hit: "it briefly shows its own wallpaper but then immediately reverts to the usual
  # default one." Quickshell's background plugin runs
  #     Timer { interval: 100; running: true; repeat: true; onTriggered: refreshBackground() }
  # which re-reads ~/.local/state/omarchy/current/background ten times a second and reasserts
  # whatever it points at. `background set` is a PREVIEW — it paints, and the very next tick
  # overwrites it. Repointing the link first is what makes the choice stick, because then every one
  # of those refreshes agrees with us.
  #
  # This is exactly what upstream's own `omarchy-theme-bg-set` does (ln -nsf, then the IPC call);
  # inlined rather than shelled out so the transition METHOD stays ours to choose.
  #
  # ⚠️ TELL THE SHELL BEFORE MOVING THE LINK, NOT AFTER — THE ORDER IS THE WHOLE ANIMATION FIX.
  # Dave, 2026-08-11: "any way to remove the wallpaper change animation when moving from one ws to
  # another?" There is, and it was never a setting. That same 100ms poll reads the link and calls
  # `setBackground(path, false)` — the `false` is "not instant", so it runs a 420ms diagonal wipe.
  # Moving the link first hands the poll a change it has not been told about, and it wipes. Worse,
  # our own instant call then does nothing at all: `transitionBackground` returns early when the
  # path it is given is already the current one, so the wipe the poll started just carries on.
  # Telling the shell first means the poll finds nothing new, so there is nothing to animate. The
  # 24ms it takes to reach the shell used to be the window the poll could win; now it is the window
  # in which the link still reads old, which is a few microseconds.
  omarchy-shell -q background "$METHOD" "$want" >/dev/null 2>&1
  ln -nsf "$want" "$STATE/background" 2>/dev/null || return 0
  # Repair, for the rare poll that read the old link in those microseconds and started a wipe back
  # to it. It is a no-op in the normal case, because by now the shell already holds this path.
  omarchy-shell -q background "$METHOD" "$want" >/dev/null 2>&1
}

# Paint the workspace we start on, so the wallpaper is right before the first switch rather than
# after it.
apply "$(hyprctl activeworkspace -j 2>/dev/null | grep -oP '"id":\s*\K[0-9]+' | head -1)"

# ⚠️ socket2, NOT a poll. It is the event stream Hyprland already emits; polling `activeworkspace`
# would be a wake-up every second for something that changes a few times an hour.
#
# ⚠️ `workspacev2`, NOT `workspace`. The plain event carries the workspace's NAME, and every
# workspace here is named — so it would deliver "Webscape" where this script needs "2". The v2 event
# is `workspacev2>>ID,NAME`, which is the only form that gives the id directly.
socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" 2>/dev/null |
  while read -r line; do
    case "$line" in
      workspacev2\>\>*) apply "${line#workspacev2>>}" ;;
    esac
  done
