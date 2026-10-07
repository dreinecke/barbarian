#!/usr/bin/env bash
# Barbarian — installer for the Omarchy Quickshell shell.
#
# Installs, user-space (no sudo), into ~/.config/omarchy:
#   plugin/ → ~/.config/omarchy/plugins/tinkerbell.arrange/   (the HYPER+B bar-arrange panel,
#                                                              the HYPER+L layouts panel that
#                                                              was Reptile, and the full-screen
#                                                              theme grid)
#   engine/per-workspace-wallpaper.sh
#           → ~/.config/omarchy/workspace-backgrounds/        (the per-desk wallpaper watcher
#                                                              the panel's bin/ scripts drive)
#   engine/ws-layout, engine/quick-app
#           → ~/.config/omarchy/workspace-layout/             (the layouts panel's engines:
#                                                              recordings, restores, quick apps)
#
# MIGRATION (2026-10-07, Q-102): until this run, Reptile was its own plugin. When the old
# tinkerbell.reptile folder is still installed, the entry is dropped from shell.json and the
# hidden sidecar, the folder goes to the trash through plugin-uninstall (entry write first,
# never a restart of its own — see that script's header), and a reminder is printed if the
# machine-local keybind still targets the old id.
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
#
# ⚠️ A WRITE IS NOT A RELOAD. Quickshell logs "Local plugin changed, reloading" and goes on
#    running the QML it compiled before, so a changed panel is only on screen after
#    `omarchy-restart-shell`. This installer does that restart itself.
#
# ⚠️ A CHANGE INSTALLS ITSELF. Every commit that touches the plugin, an engine, a hook or this
#    file runs this installer (hooks/post-commit), and nothing is left to be run by hand — Dave,
#    2026-09-21: "Please auto update always upon unlock." So a run that cannot write, because the
#    screen is locked or Barbarian's own panel is on screen, ARMS A WAITER: a transient systemd
#    user service running `install.sh --when-unlocked`, which polls and finishes the job the
#    moment the screen is free. Nothing polls while nothing is waiting, and a second run adds no
#    second waiter. The gap left: a commit made while locked, then a reboot before the unlock —
#    the next commit, a run by hand, or the machine's daily self-heal picks it up.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="tinkerbell.arrange"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
ENGINE_DST="$HOME/.config/omarchy/workspace-backgrounds/per-workspace-wallpaper.sh"
LAYOUT_DST="$HOME/.config/omarchy/workspace-layout"
OLD_PLUGIN_DIR="$HOME/.config/omarchy/plugins/tinkerbell.reptile"
WAIT_UNIT="barbarian-install-pending"
# A plugin file written while the screen is locked cannot be compiled then: restarting Quickshell
# would unlock the machine. This file says a restart is owed, and the next free run does it.
RESTART_STAMP="$HOME/.local/state/omarchy/barbarian-restart-owed"
UNLOCK_POLL=10
UNLOCK_GIVE_UP=21600      # six hours of locked screen, then leave it to the next run

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

# The panel being installed may be the one on screen: writing its files reloads the plugin under
# the user's hands, and the restart below would take the panel away mid-gesture. An unreachable
# hyprctl (ssh, no session) means no panel — never wait on a question that cannot be answered.
panel_open() {
  hyprctl layers -j 2>/dev/null | grep -q omarchy-keyboard-panel
}

# A desk renumber runs detached, outliving the panel, and spends a few seconds with the desks
# parked at spare ids between two config reloads. Nothing is installed into that window.
renumbering() {
  pgrep -u "$(id -u)" -f '[b]in/ws-renumber' >/dev/null 2>&1
}

busy() { session_locked || panel_open || renumbering; }

# `--when-unlocked` is the waiter: wait for the screen (and the panel, and any renumber), then
# install as usual.
if [ "${1:-}" = "--when-unlocked" ]; then
  waited=0
  while busy; do
    if [ "$waited" -ge "$UNLOCK_GIVE_UP" ]; then
      echo "barbarian: six hours locked or busy; the next commit, run or self-heal installs it"
      exit 0
    fi
    sleep "$UNLOCK_POLL"
    waited=$((waited + UNLOCK_POLL))
  done
fi

arm_waiter() {
  command -v systemd-run >/dev/null 2>&1 || return 0
  systemctl --user is-active --quiet "$WAIT_UNIT" 2>/dev/null && return 0   # one waiter is enough
  systemd-run --user --collect --quiet --unit="$WAIT_UNIT" \
    --description="Barbarian installs itself when the screen unlocks" \
    "$HERE/install.sh" --when-unlocked >/dev/null 2>&1
}

# Nothing running is nothing to restart: the next shell to start reads the new files anyway.
SHELL_NOTE=""
restart_shell() {
  if ! pgrep -u "$(id -u)" -x quickshell >/dev/null 2>&1; then
    SHELL_NOTE="and no shell was running, so the next one to start shows the panel"
    return 0
  fi
  omarchy-restart-shell >/dev/null 2>&1 || return 1   # it refuses on its own while locked
  SHELL_NOTE="and the shell restarted for the panel"
  return 0
}

# The wallpaper engine is a long-running watcher (Restart=always), so a new copy on disk changes
# nothing until its unit restarts. The unit is the machine's, not this repo's, and it writes the
# path with systemd's %h, so it is found by the script's name.
restart_engine() {
  local unit
  for unit in "$HOME"/.config/systemd/user/*.service; do
    [ -f "$unit" ] || continue
    grep -q 'per-workspace-wallpaper\.sh' "$unit" || continue
    systemctl --user try-restart "$(basename "$unit")" 2>/dev/null || true
  done
}

# 🛑 A BROKEN ENGINE IS NEVER INSTALLED (Reptile's rule, carried over): ws-layout runs from a
#    key press and an installer that wrote a file with a syntax error in it would take HYPER+R
#    and HYPER+S away until someone read a log. The panels cannot be checked this way —
#    Quickshell compiles QML itself — but a write is not a reload, so a broken panel only
#    shows up at the next restart.
compiles() {
  python3 - "$1" <<'PY'
import os, py_compile, sys, tempfile
cache = tempfile.NamedTemporaryFile(suffix=".pyc", delete=False)
cache.close()
try:
    py_compile.compile(sys.argv[1], cfile=cache.name, doraise=True)
finally:
    os.unlink(cache.name)
PY
}
for engine in ws-layout quick-app; do
  if ! compiles "$HERE/engine/$engine"; then
    echo "barbarian: engine/$engine does not compile — nothing installed"
    exit 1
  fi
done

DEFERRED=0
PLUGIN_CHANGED=0
ENGINE_CHANGED=0
install_plugin_file() { # <mode> <repo file> <live file>
  local mode="$1" src="$2" dest="$3"
  cmp -s "$src" "$dest" && return 0        # identical — no write, no reload
  if busy; then
    DEFERRED=$((DEFERRED + 1))
    return 0
  fi
  install -D"$mode" "$src" "$dest"
  case "$dest" in
    "$PLUGIN_DIR"/*) PLUGIN_CHANGED=1 ;;
    "$ENGINE_DST")   ENGINE_CHANGED=1 ;;
  esac
}

# Everything this installer writes, mode|repo file|live file. The manifest stays LAST in
# the list: it names ThemeRemover.qml as the overlay, and a manifest that arrives before the
# file it names leaves the shell with an overlay that fails to load.
FILES=(
  "m644|$HERE/plugin/ReorderController.qml|$PLUGIN_DIR/ReorderController.qml"
  "m644|$HERE/plugin/ReorderRow.qml|$PLUGIN_DIR/ReorderRow.qml"
  "m644|$HERE/plugin/Panel.qml|$PLUGIN_DIR/Panel.qml"
  "m644|$HERE/plugin/Reptile.qml|$PLUGIN_DIR/Reptile.qml"
  "m755|$HERE/plugin/bin/bar-arrange-apply|$PLUGIN_DIR/bin/bar-arrange-apply"
  "m755|$HERE/plugin/bin/ws-bg-pick|$PLUGIN_DIR/bin/ws-bg-pick"
  "m755|$HERE/plugin/bin/ws-bg-add|$PLUGIN_DIR/bin/ws-bg-add"
  "m755|$HERE/plugin/bin/ws-bg-remove|$PLUGIN_DIR/bin/ws-bg-remove"
  "m755|$HERE/plugin/bin/ws-bg-restore|$PLUGIN_DIR/bin/ws-bg-restore"
  "m755|$HERE/plugin/bin/ws-renumber|$PLUGIN_DIR/bin/ws-renumber"
  "m755|$HERE/plugin/bin/barbarian-stash|$PLUGIN_DIR/bin/barbarian-stash"
  "m644|$HERE/plugin/ThemeCard.qml|$PLUGIN_DIR/ThemeCard.qml"
  "m644|$HERE/plugin/ThemeGrid.qml|$PLUGIN_DIR/ThemeGrid.qml"
  "m644|$HERE/plugin/ThemeStore.qml|$PLUGIN_DIR/ThemeStore.qml"
  "m644|$HERE/plugin/ThemeRemover.qml|$PLUGIN_DIR/ThemeRemover.qml"
  "m755|$HERE/plugin/bin/theme-remover|$PLUGIN_DIR/bin/theme-remover"
  "m755|$HERE/plugin/bin/plugin-uninstall|$PLUGIN_DIR/bin/plugin-uninstall"
  "m644|$HERE/plugin/manifest.json|$PLUGIN_DIR/manifest.json"
  "m755|$HERE/engine/per-workspace-wallpaper.sh|$ENGINE_DST"
  "m755|$HERE/engine/ws-layout|$LAYOUT_DST/ws-layout"
  "m755|$HERE/engine/quick-app|$LAYOUT_DST/quick-app"
)

# ⚠️ THE SHELL IS STOPPED BEFORE A PLUGIN WRITE (2026-10-07, three SIGSEGVs: 11:36:15,
#    11:39:32, 11:40:52 — enterprise's write-up lives in its docs/omarchy-setup.md). A write
#    under plugins/ with the shell running fires its watcher's reload, and the restart half a
#    second later lands while that reload is still finishing: Quickshell dies in
#    IpcHandler::updateRegistration — the same frame as 2026-09-26 and the four-bar day.
#    So when a plugin file is about to change and the screen is free, the shell is stopped
#    FIRST (omarchy-restart-shell's own kill loop, minus the launch): no watcher is alive,
#    the writes reload nothing, and the restart afterwards is the run's one and only reload.
plugin_write_pending=0
for f in "${FILES[@]}"; do
  rest="${f#*|}"; src="${rest%%|*}"; dest="${f##*|}"
  case "$dest" in
    "$PLUGIN_DIR"/*) cmp -s "$src" "$dest" || plugin_write_pending=1 ;;
  esac
done

SHELL_STOPPED=0
if [ "$plugin_write_pending" = 1 ] && ! busy; then
  omarchy_path="$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)"
  : "${omarchy_path:=$OMARCHY_PATH}"
  while timeout 5 quickshell kill -p "$omarchy_path/shell" --any-display >/dev/null 2>&1; do :; done
  SHELL_STOPPED=1
fi

for f in "${FILES[@]}"; do
  rest="${f#*|}"; src="${rest%%|*}"; dest="${f##*|}"
  install_plugin_file "${f%%|*}" "$src" "$dest"
done

# The engine is normally started by a user service or a theme-set hook on the host
# machine; it is safe to install everywhere and started where the wiring exists.
[ "$ENGINE_CHANGED" = 1 ] && restart_engine

# The old Reptile plugin (see the header): the entry leaves both files FIRST, then the folder —
# the order plugin-uninstall waits for. It runs synchronously, not detached: the installer is
# already the detached thing, and this way the trash lands before the restart below, which then
# clears the stamp plugin-uninstall leaves. One restart, in order, once.
if [ -d "$OLD_PLUGIN_DIR" ] && ! busy; then
  python3 - <<'PY'
import json, os, tempfile

OLD = "tinkerbell.reptile"
LANES = ("left", "center", "right")

def rewrite(path, transform):
    if not os.path.exists(path):
        return
    with open(path) as f:
        data = json.load(f)
    if not transform(data):
        return
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix="." + os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise

def clean_layout(data):
    layout = data.get("bar", {}).get("layout", {})
    changed = False
    for lane in LANES:
        rows = layout.get(lane, [])
        kept = [e for e in rows if e.get("id") != OLD]
        if len(kept) != len(rows):
            layout[lane] = kept
            changed = True
    return changed

def clean_sidecar(data):
    changed = False
    for lane in LANES:
        rows = data.get(lane, [])
        kept = [r for r in rows if (r.get("entry") or {}).get("id") != OLD]
        if len(kept) != len(rows):
            data[lane] = kept
            changed = True
    return changed

home = os.path.expanduser("~")
rewrite(home + "/.config/omarchy/shell.json", clean_layout)
rewrite(home + "/.config/omarchy/bar-hidden.json", clean_sidecar)
PY
  if "$HERE/plugin/bin/plugin-uninstall" tinkerbell.reptile; then
    echo "barbarian: Reptile merged in — the old plugin's folder went to the trash"
  else
    echo "barbarian: the old Reptile folder is still installed; the next run tries again"
  fi
  if grep -q "tinkerbell.reptile" "$HOME/.config/hypr/bindings.lua" 2>/dev/null; then
    echo "barbarian: keybind reminder — in ~/.config/hypr/bindings.lua change"
    echo "  omarchy-shell tinkerbell.reptile toggle  →  omarchy-shell tinkerbell.arrange layouts"
  fi
fi

# A restart is owed when this run wrote a plugin file, or when an earlier one did and the screen
# went up before it could be compiled.
RESTART_OWED=0
[ -f "$RESTART_STAMP" ] && RESTART_OWED=1
[ "$PLUGIN_CHANGED" = 1 ] && RESTART_OWED=1

# A stopped shell owes its start no matter what else is true — nothing below may leave it
# down. The writes fired no watcher reloads (nothing was watching), so this start is the
# run's one and only reload; the crash race cannot exist.
if [ "$SHELL_STOPPED" = 1 ]; then
  if omarchy-restart-shell >/dev/null 2>&1; then
    rm -f "$RESTART_STAMP"
    SHELL_NOTE="and the shell restarted for the panel"
  else
    # The screen went up while it was down; the waiter finishes the job.
    mkdir -p "$(dirname "$RESTART_STAMP")"
    : > "$RESTART_STAMP"
    arm_waiter
    SHELL_NOTE="; the shell restarts when the screen is free"
  fi
fi

if [ "$DEFERRED" -gt 0 ]; then
  # The screen went up part way through: some files are in, the rest are not. A panel file among
  # the ones that went in is owed a restart the waiter's own run would not know about, because by
  # then only the files it has left to write look changed.
  if [ "$PLUGIN_CHANGED" = 1 ]; then
    mkdir -p "$(dirname "$RESTART_STAMP")"
    : > "$RESTART_STAMP"
  fi
  arm_waiter
  echo "barbarian: $DEFERRED file(s) held back — the screen is locked or the panel is open; they go in the moment it clears"
elif [ "$SHELL_STOPPED" = 1 ]; then
  echo "barbarian: installed to $PLUGIN_DIR and $ENGINE_DST, $SHELL_NOTE"
elif [ "$RESTART_OWED" = 1 ]; then
  if ! busy && restart_shell; then
    rm -f "$RESTART_STAMP"
    echo "barbarian: installed to $PLUGIN_DIR and $ENGINE_DST, $SHELL_NOTE"
  else
    # The screen went up between the write and the restart; the waiter finishes the job.
    mkdir -p "$(dirname "$RESTART_STAMP")"
    : > "$RESTART_STAMP"
    arm_waiter
    echo "barbarian: installed to $PLUGIN_DIR and $ENGINE_DST; the shell restarts when the screen is free"
  fi
else
  echo "barbarian: installed to $PLUGIN_DIR and $ENGINE_DST"
fi

# post-commit hook (not tracked by git): a commit touching the plugin, an engine, a hook or this
# file installs itself, and on the machine that owns the mirror ships it also triggers the ship
# sync, same as the machine repo's own hook.
if [ -d "$HERE/.git" ]; then
  install -Dm755 "$HERE/hooks/post-commit" "$HERE/.git/hooks/post-commit"
fi
