#!/usr/bin/env bash
# per-workspace-wallpaper.sh — Tinkerbell, Omarchy setup v0.7 (2026-06-06)
# Reworked for T78 (v0.48, 2026-06-11): solid colour-coded workspaces.
#
# Gives each Hyprland workspace its own background by swapping swaybg whenever
# the active workspace changes. Dependency-free: it reuses Omarchy's OWN swaybg
# mechanism (the same pkill + relaunch that `omarchy-theme-bg-next` uses), so
# there's no swww to install and no fight with the theme background setter.
#
# Mapping (edit freely) — David's colour code, T78:
#   workspace 1 "Google"      -> solid #D7ECC5 (green  = Google)
#   workspace 2 "Webscape"    -> solid #E3F7F9 (blue   = Webscape, from logo)
#   workspace 3 "Personal"    -> solid #FFFDEE (yellow = Personal)
#   workspace 4 "Development" -> solid #353839 (dark   = Development)
#   everything else (5-9, 10/"0", special/"S") -> the live theme background,
#     pointed at via the ~/.config/omarchy/current/background symlink, so those
#     workspaces follow `omarchy theme` changes automatically.
#
# A "#RRGGBB" token means a solid colour (swaybg -c); anything else is an image
# path (swaybg -i). NOTE: socket2 `workspace>>` events carry the workspace
# NAME, so with defaultName set (workspaces.conf) the case arms must match
# both the number and the name.
#
# De-dupe: swaybg is only restarted when the target actually changes, so
# moving among the "default" workspaces causes no flicker.

set -u
DEFAULT_LINK="$HOME/.config/omarchy/current/background"   # symlink; follows the theme

# Seed with what swaybg is already showing (image or colour), so we don't
# pointlessly restart it at launch when the focused workspace already matches.
LAST_BG="$(pgrep -af '[s]waybg' | grep -oP ' (-i \K[^ ]+|-c \K#?[0-9A-Fa-f]{6})' | head -1)"

wallpaper_for() {
  case "$1" in
    1|Google)      printf '#D7ECC5' ;;
    2|Webscape)    printf '#E3F7F9' ;;
    3|Personal)    printf '#FFFDEE' ;;
    4|Development) printf '#353839' ;;
    *)             printf '%s' "$DEFAULT_LINK" ;;
  esac
}

run_swaybg() {
  if command -v uwsm-app >/dev/null 2>&1; then
    setsid uwsm-app -- swaybg "$@" >/dev/null 2>&1 &
  else
    setsid swaybg "$@" >/dev/null 2>&1 &
  fi
}

apply() {
  local bg
  bg="$(wallpaper_for "$1")"
  case "$bg" in
    \#*) ;;                                  # solid colour token
    *)   [ -e "$bg" ] || bg="$DEFAULT_LINK" ;;
  esac
  [ "$bg" = "$LAST_BG" ] && return
  LAST_BG="$bg"
  pkill -x swaybg 2>/dev/null
  case "$bg" in
    \#*) run_swaybg -c "${bg#\#}" -m solid_color ;;
    *)   run_swaybg -i "$bg" -m fill ;;
  esac
}

active_ws() { hyprctl activeworkspace -j 2>/dev/null | grep -oP '"name"\s*:\s*"\K[^"]+' | head -1; }

# Wallpaper for whatever workspace is focused at launch.
apply "$(active_ws)"

# Stream Hyprland events; re-derive on monitor-focus changes; reconnect if the
# compositor restarts its event socket.
SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
while :; do
  socat -U - "UNIX-CONNECT:${SOCK}" 2>/dev/null | while read -r line; do
    case "$line" in
      workspace\>\>*)     apply "${line#workspace>>}" ;;
      focusedmon\>\>*)    apply "$(active_ws)" ;;
      activespecial\>\>*) apply "special" ;;
    esac
  done
  sleep 1
done
