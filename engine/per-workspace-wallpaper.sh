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
# (e.g. `ws4.png`) — an override always wins over the theme's list.

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

# Which image workspace N should show. An explicit ws<N>.<ext> override beats the theme; otherwise
# index into the theme's list, wrapping if the theme ships fewer images than there are workspaces.
wallpaper_for() {
  local ws="$1" override
  for override in "$HERE/ws$ws".*; do
    [ -f "$override" ] && { printf '%s' "$override"; return 0; }
  done

  local -a list
  mapfile -t list < <(theme_backgrounds)
  [ "${#list[@]}" -gt 0 ] || return 0
  printf '%s' "${list[$(( (ws - 1) % ${#list[@]} ))]}"
}

LAST=""
apply() {
  local ws="$1" want
  # ⚠️ THE v2 EVENT IS `ID,NAME` AND ONLY THE ID IS WANTED. Passed through whole, the id lands in an
  # arithmetic expression as `2,Webscape` — bash reads the comma as the sequence operator, evaluates
  # `Webscape` as a variable name, and dies on `set -u`. Strip at the first comma.
  ws="${ws%%,*}"
  case "$ws" in ''|*[!0-9]*) return 0 ;; esac
  want="$(wallpaper_for "$ws")" || return 0
  [ -n "$want" ] || return 0
  # ⚠️ DE-DUPE OR IT REPAINTS ON EVERY SWITCH. Two workspaces can resolve to the same image (a theme
  # with fewer backgrounds than workspaces wraps), and re-setting the same path is a visible flicker
  # for no change.
  [ "$want" = "$LAST" ] && return 0
  omarchy-shell background "$METHOD" "$want" >/dev/null 2>&1 && LAST="$want"
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
