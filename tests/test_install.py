#!/usr/bin/env python3
"""Tests for install.sh's update mechanism — what it writes, and when it waits.

    python3 tests/test_install.py

Every run uses a throwaway HOME and a stub PATH, so the live plugin, the live shell and systemd
are never touched: `omarchy-shell` answers whatever the test says the lock is, and
`omarchy-restart-shell`, `systemd-run` and `systemctl` only write down that they were called.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "install.sh"
PLUGIN = ".config/omarchy/plugins/tinkerbell.arrange"

STUB = """#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$CALLS"
{body}
"""


class Install(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.calls = self.tmp / "calls"
        self.calls.touch()
        # A shell to find, so the installer does not take "nothing running" for "nothing locked",
        # and no renumber in flight. Stubbed rather than run, so the tests never depend on — or
        # wait for — what happens to be running on the machine.
        self.stub("pgrep", 'case "$*" in *quickshell*) echo 1234 ;; *) exit 1 ;; esac')
        self.stub("omarchy-restart-shell", "exit 0")
        self.stub("systemd-run", "exit 0")
        # No waiter is armed yet: `is-active` on a unit that is not running exits 3.
        self.stub("systemctl", 'case "$*" in *is-active*) exit 3 ;; *) exit 0 ;; esac')
        self.stub("hyprctl", 'echo "[]"')          # no panel on screen
        self.locked(False)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(STUB.format(body=body))
        path.chmod(0o755)

    def locked(self, yes):
        self.stub("omarchy-shell", f'echo \'{{"sessionLocked":{str(bool(yes)).lower()}}}\'')

    def run_install(self, *args):
        env = {"HOME": str(self.home), "PATH": f"{self.bin}:{os.environ['PATH']}",
               "CALLS": str(self.calls), "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", "/tmp")}
        return subprocess.run([str(SCRIPT), *args], capture_output=True, text=True, env=env)

    def called(self, name):
        return [line for line in self.calls.read_text().splitlines() if line.startswith(name)]

    def installed(self):
        return sorted(p.name for p in (self.home / PLUGIN).rglob("*") if p.is_file())

    def test_an_unlocked_run_installs_and_restarts_the_shell(self):
        result = self.run_install()
        self.assertIn("Panel.qml", self.installed())
        self.assertTrue(self.called("omarchy-restart-shell"), result.stdout + result.stderr)
        self.assertIn("the shell restarted", result.stdout)

    def test_a_locked_run_writes_nothing_and_arms_the_waiter(self):
        self.locked(True)
        result = self.run_install()
        self.assertFalse((self.home / PLUGIN).exists())
        self.assertFalse(self.called("omarchy-restart-shell"))
        self.assertTrue(self.called("systemd-run"))
        self.assertIn("--when-unlocked", self.called("systemd-run")[0])
        self.assertIn("held back", result.stdout)

    def test_the_panel_on_screen_counts_as_busy(self):
        self.stub("hyprctl", 'echo \'[{"namespace": "omarchy-keyboard-panel"}]\'')
        self.run_install()
        self.assertFalse((self.home / PLUGIN).exists())
        self.assertTrue(self.called("systemd-run"))

    def test_a_restart_owed_from_a_locked_run_happens_at_the_next_free_one(self):
        self.locked(True)
        self.run_install()
        self.locked(False)
        result = self.run_install()
        self.assertIn("Panel.qml", self.installed())
        self.assertTrue(self.called("omarchy-restart-shell"))
        # Installed and restarted: nothing is owed any more.
        self.assertFalse((self.home / ".local/state/omarchy/barbarian-restart-owed").exists())
        self.assertIn("the shell restarted", result.stdout)

    def test_a_second_run_changes_nothing_and_leaves_the_shell_alone(self):
        self.run_install()
        (self.calls).write_text("")
        result = self.run_install()
        self.assertFalse(self.called("omarchy-restart-shell"))
        self.assertNotIn("restart", result.stdout)

    def test_a_refused_restart_is_owed_rather_than_forgotten(self):
        self.stub("omarchy-restart-shell", "exit 1")     # what it does while the session is locked
        self.run_install()
        self.assertIn("Panel.qml", self.installed())
        self.assertTrue((self.home / ".local/state/omarchy/barbarian-restart-owed").exists())
        self.assertTrue(self.called("systemd-run"))

    def test_the_wallpaper_engine_unit_is_restarted_when_the_engine_changes(self):
        unit = self.home / ".config/systemd/user/some-wallpaper.service"
        unit.parent.mkdir(parents=True)
        unit.write_text("[Service]\nExecStart=%h/.config/omarchy/workspace-backgrounds/"
                        "per-workspace-wallpaper.sh\n")
        self.run_install()
        self.assertTrue([c for c in self.called("systemctl") if "try-restart" in c])

    def test_the_waiter_installs_once_the_screen_is_free(self):
        result = self.run_install("--when-unlocked")
        self.assertIn("Panel.qml", self.installed())
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main()
