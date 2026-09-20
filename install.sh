#!/usr/bin/env bash
# Barbarian — installer for the Omarchy Quickshell shell.
#
# Installs, user-space (no sudo), into ~/.config/omarchy:
#   plugin/ → ~/.config/omarchy/plugins/tinkerbell.arrange/   (the HYPER+B bar-arrange panel)
#   engine/per-workspace-wallpaper.sh
#           → ~/.config/omarchy/workspace-backgrounds/        (the per-desk wallpaper watcher
#                                                              the panel's bin/ scripts drive)
#
# Idempotent: re-running is the repair.
#
# 🛑 EVERY PLUGIN FILE GOES IN THROUGH `install_plugin_file`, NEVER `install` DIRECTLY.
#    Writing a plugin file triggers a shell reload — Quickshell watches the plugins
#    directory and rebuilds its entire QML root, lock service included — and a reload
#    while the session is LOCKED aborts the shell (it recovers, the machine stays
#    locked, but nothing unattended should do it). So: compare first and skip when
#    identical, and DEFER the write when the session is locked or unreadable.
#    Unreadable means locked — a wrong "locked" costs a few hours' delay; a wrong
#    "unlocked" costs the crash. The full history of these rules lives in the
#    machine repo this was extracted from (dreinecke/enterprise, private).
#    This reload may reuse cached QML. After installing code changes, a full
#    `omarchy restart shell` while unlocked is required to activate them reliably.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="tinkerbell.arrange"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
ENGINE_DST="$HOME/.config/omarchy/workspace-backgrounds/per-workspace-wallpaper.sh"

# A plain ssh login has neither of these, and without them the lock cannot be read at all — the
# shell's own `omarchy-shell` refuses with "OMARCHY_PATH is not set" (2026-09-20). Defaults, not
# overrides: a real session's values are left alone.
[ -n "${OMARCHY_PATH:-}" ] || export OMARCHY_PATH=/usr/share/omarchy
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for sock in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/wayland-[0-9]*; do
    [ -S "$sock" ] && export WAYLAND_DISPLAY="$(basename "$sock")" && break
  done
fi

session_locked() {
  local status
  # ⚠️ NO SHELL RUNNING MEANS NOTHING TO CRASH — and it is the case `omarchy-shell lock status`
  # cannot answer: over a plain ssh login it prints "OMARCHY_PATH is not set", which the
  # fall-through below read as a lock, so a stranger installing over ssh had every file deferred
  # with a message blaming a lock that did not exist (found on a stock machine, 2026-09-20).
  pgrep -u "$(id -u)" -x quickshell >/dev/null 2>&1 || return 1
  status="$(omarchy-shell lock status 2>/dev/null)"
  case "$status" in
    *'"sessionLocked":true'*)  return 0 ;;   # a lock is up
    *'"pending":true'*)        return 0 ;;   # a lock was asked for and never finished
    *'"sessionLocked":false'*) return 1 ;;
  esac
  [ "$(omarchy-shell lock isLocked 2>/dev/null)" != "false" ]
}

DEFERRED=0
install_plugin_file() { # <mode> <repo file> <live file>
  local mode="$1" src="$2" dest="$3"
  cmp -s "$src" "$dest" && return 0        # identical — no write, no reload
  if session_locked; then
    DEFERRED=$((DEFERRED + 1))
    return 0
  fi
  install -D"$mode" "$src" "$dest"
}

install_plugin_file m644 "$HERE/plugin/manifest.json"         "$PLUGIN_DIR/manifest.json"
install_plugin_file m644 "$HERE/plugin/ReorderController.qml" "$PLUGIN_DIR/ReorderController.qml"
install_plugin_file m644 "$HERE/plugin/ReorderRow.qml"        "$PLUGIN_DIR/ReorderRow.qml"
install_plugin_file m644 "$HERE/plugin/Panel.qml"             "$PLUGIN_DIR/Panel.qml"
install_plugin_file m755 "$HERE/plugin/bin/bar-arrange-apply" "$PLUGIN_DIR/bin/bar-arrange-apply"
install_plugin_file m755 "$HERE/plugin/bin/ws-bg-pick"        "$PLUGIN_DIR/bin/ws-bg-pick"
install_plugin_file m755 "$HERE/plugin/bin/ws-bg-add"         "$PLUGIN_DIR/bin/ws-bg-add"
install_plugin_file m755 "$HERE/plugin/bin/ws-bg-remove"      "$PLUGIN_DIR/bin/ws-bg-remove"
install_plugin_file m755 "$HERE/plugin/bin/ws-bg-restore"     "$PLUGIN_DIR/bin/ws-bg-restore"
install_plugin_file m755 "$HERE/plugin/bin/ws-renumber"       "$PLUGIN_DIR/bin/ws-renumber"
install_plugin_file m755 "$HERE/plugin/bin/barbarian-stash"   "$PLUGIN_DIR/bin/barbarian-stash"
install_plugin_file m755 "$HERE/engine/per-workspace-wallpaper.sh" "$ENGINE_DST"

# The engine is normally started by a user service or a theme-set hook on the host
# machine; it is safe to install everywhere and started where the wiring exists.
if [ "$DEFERRED" -gt 0 ]; then
  echo "barbarian: $DEFERRED file(s) deferred — the screen is locked (or the lock cannot be read); re-run unlocked"
else
  echo "barbarian: installed to $PLUGIN_DIR and $ENGINE_DST"
  echo "barbarian: restart the shell while unlocked to load code changes: omarchy restart shell"
fi

# post-commit hook (not tracked by git): on the machine that owns the mirror ships,
# a commit touching plugin/ or engine/ triggers the ship sync, same as the machine
# repo's own hook. Everywhere else this installs a no-op.
if [ -d "$HERE/.git" ]; then
  install -Dm755 "$HERE/hooks/post-commit" "$HERE/.git/hooks/post-commit"
fi
