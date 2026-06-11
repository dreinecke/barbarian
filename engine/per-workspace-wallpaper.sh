#!/usr/bin/env bash
# per-workspace-wallpaper.sh — Tinkerbell, Omarchy setup v0.7 (2026-06-06)
# T78 (v0.48): solid colour-coded workspaces. T83 (v0.54): wallpapers went
# uniform dark and the per-workspace colour moved UP into the waybar — this
# one socket2 listener now drives both surfaces (one listener, not two, per
# David's research doc).
#
#   wallpaper — all five named workspaces get a uniform solid #353839 (the
#     old "Development" dark); everything else (6-9, 10/"0", special/"S")
#     follows the live theme background via the
#     ~/.config/omarchy/current/background symlink.
#
#   waybar — @define-color barbg/barfg in ~/.config/waybar/workspace-colors.css
#     are rewritten per workspace (David's Option A palette, decision aid
#     RT84); waybar repaints on the write via reload_style_on_change.
#     Non-named workspaces alias the theme's own @background/@foreground, so
#     they follow `omarchy theme` changes automatically.
#
# Wallpaper swaps reuse Omarchy's OWN swaybg mechanism (the same pkill +
# relaunch that `omarchy-theme-bg-next` uses) — no swww, no fight with the
# theme background setter. A "#RRGGBB" token means a solid colour (swaybg -c);
# anything else is an image path (swaybg -i).
#
# NOTE: socket2 `workspace>>` events carry the workspace NAME, so with
# defaultName set (workspaces.conf) the case arms must match both the number
# and the name. Both surfaces de-dupe: swaybg only restarts and the CSS file
# is only rewritten when the target actually changes, so moving among
# same-coloured workspaces causes no flicker and no spurious repaints.

set -u
DEFAULT_LINK="$HOME/.config/omarchy/current/background"   # symlink; follows the theme
WAYBAR_COLORS="$HOME/.config/waybar/workspace-colors.css"

# Seed with what swaybg is already showing (image or colour), so we don't
# pointlessly restart it at launch when the focused workspace already matches.
LAST_BG="$(pgrep -af '[s]waybg' | grep -oP ' (-i \K[^ ]+|-c \K#?[0-9A-Fa-f]{6})' | head -1)"
LAST_BAR=""

wallpaper_for() {
  case "$1" in
    1|Google|2|Webscape|3|Personal|4|Gandalf|5|Tinkerbell) printf '#353839' ;;
    *) printf '%s' "$DEFAULT_LINK" ;;
  esac
}

# "barbg barfg" per workspace — Option A (RT84): full palette bars, dark text.
bar_colors_for() {
  case "$1" in
    1|Google)     printf '#D7ECC5 #141413' ;;   # green   = Google
    2|Webscape)   printf '#E3F7F9 #141413' ;;   # blue    = Webscape
    3|Personal)   printf '#FFFDEE #141413' ;;   # yellow  = Personal
    4|Gandalf)    printf '#E8D3A2 #141413' ;;   # gold    = Gandalf
    5|Tinkerbell) printf '#F0D9F4 #141413' ;;   # pink    = Tinkerbell
    *)            printf '@background @foreground' ;;   # theme passthrough
  esac
}

run_swaybg() {
  if command -v uwsm-app >/dev/null 2>&1; then
    setsid uwsm-app -- swaybg "$@" >/dev/null 2>&1 &
  else
    setsid swaybg "$@" >/dev/null 2>&1 &
  fi
}

apply_wall() {
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

apply_bar() {
  local pair
  pair="$(bar_colors_for "$1")"
  [ "$pair" = "$LAST_BAR" ] && return
  LAST_BAR="$pair"
  printf '@define-color barbg %s;\n@define-color barfg %s;\n' \
    "${pair% *}" "${pair#* }" > "$WAYBAR_COLORS"
}

apply() { apply_wall "$1"; apply_bar "$1"; }

active_ws() { hyprctl activeworkspace -j 2>/dev/null | grep -oP '"name"\s*:\s*"\K[^"]+' | head -1; }

# Both surfaces for whatever workspace is focused at launch.
apply "$(active_ws)"

# Stream Hyprland events; re-derive on monitor-focus changes; reconnect if the
# compositor restarts its event socket. activespecial>> fires with an empty
# name when the special workspace CLOSES — re-derive the real workspace then.
SOCK="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
while :; do
  socat -U - "UNIX-CONNECT:${SOCK}" 2>/dev/null | while read -r line; do
    case "$line" in
      workspace\>\>*)      apply "${line#workspace>>}" ;;
      focusedmon\>\>*)     apply "$(active_ws)" ;;
      activespecial\>\>,*) apply "$(active_ws)" ;;
      activespecial\>\>*)  apply "special" ;;
    esac
  done
  sleep 1
done
