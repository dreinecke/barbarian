#!/usr/bin/env python3
"""Tests for plugin/bin/plugin-uninstall — the folder half of an uninstall (the entry half is
bar-arrange-apply's DEL:<id>, covered in test_bar_arrange_apply.py).

    python3 tests/test_plugin_uninstall.py

Every run uses a throwaway HOME with a plugins folder, so the trash the folder goes to is the
throwaway's own. `omarchy-shell`, `omarchy-restart-shell`, `omarchy-notification-send` and
`pgrep` are stubs that only write down or answer what the script asks, so no real shell is
restarted and no real lock is read; `gio trash` is the real one (a standard Omarchy install
ships it, and it only moves things inside the throwaway HOME).
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "plugin/bin/plugin-uninstall"

STUB = """#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$CALLS"
{body}
"""


class Uninstall(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home = self.tmp / "home"
        self.plugins = self.home / ".config/omarchy/plugins"
        self.plugins.mkdir(parents=True)
        for pid in ("some.plug", "other.plug", "tinkerbell.arrange"):
            (self.plugins / pid).mkdir()
            (self.plugins / pid / "manifest.json").write_text("{}\n")
        (self.plugins / "not.a.plugin").mkdir()          # no manifest: not a plugin
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.calls = self.tmp / "calls"
        self.calls.touch()
        # pgrep answers as though the session's shell is running (so the lock is consulted)
        # and nothing is ever mid-renumber.
        self.stub("pgrep", 'case "$*" in *ws-renumber*) exit 1 ;; *) exit 0 ;; esac')
        self.stub("omarchy-shell", 'if [ "$1" = "lock" ]; then echo \'{"sessionLocked":false}\'; fi')
        self.stub("omarchy-restart-shell", "exit 0")
        self.stub("omarchy-notification-send", "exit 0")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(STUB.format(body=body))
        path.chmod(0o755)

    def env(self, **extra):
        # OMARCHY_PATH is the stub bin on purpose: the script prepends "$OMARCHY_PATH/bin"
        # to PATH, so without this the real /usr/share/omarchy/bin shadows every stub.
        # The settles are zeroed: the spacing they buy is timing against a live shell,
        # and what the tests check is that the stages happen in the right ORDER.
        env = {"HOME": str(self.home), "XDG_RUNTIME_DIR": str(self.tmp),
               "OMARCHY_PATH": str(self.bin), "BARBARIAN_UNINSTALL_SETTLE": "0",
               "PATH": f"{self.bin}:{os.environ['PATH']}", "CALLS": str(self.calls)}
        env.update(extra)
        return env

    def run_script(self, *args, **extra):
        return subprocess.run([str(SCRIPT), *map(str, args)], capture_output=True, text=True,
                              env=self.env(**extra))

    def trash_names(self):
        files = self.home / ".local/share/Trash/files"
        return [p.name for p in files.iterdir()] if files.is_dir() else []

    def test_uninstall_moves_the_folder_to_the_trash(self):
        result = self.run_script("some.plug")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.plugins / "some.plug").exists())
        self.assertTrue(any(n.startswith("some.plug") for n in self.trash_names()),
                        self.trash_names())

    def test_uninstall_leaves_the_other_plugins_alone(self):
        self.run_script("some.plug")
        self.assertTrue((self.plugins / "other.plug" / "manifest.json").exists())

    def test_the_folder_waits_for_the_entry_to_leave_the_bar(self):
        """The trash must not land while the layout still names the plugin (see the header)."""
        (self.home / ".config/omarchy/shell.json").write_text(
            '{"bar": {"layout": {"left": [], "center": [], '
            '"right": [{"id": "some.plug"}]}}}\n')
        result = self.run_script("some.plug", BARBARIAN_UNINSTALL_WAIT="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.plugins / "some.plug" / "manifest.json").exists())
        self.assertNotIn("omarchy-restart-shell", self.calls.read_text())

    def test_the_folder_leaves_once_the_layout_no_longer_names_it(self):
        (self.home / ".config/omarchy/shell.json").write_text(
            '{"bar": {"layout": {"left": [], "center": [], '
            '"right": [{"id": "other.plug"}]}}}\n')
        result = self.run_script("some.plug", BARBARIAN_UNINSTALL_WAIT="0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.plugins / "some.plug").exists())

    def test_uninstall_restarts_the_shell_by_default(self):
        self.run_script("some.plug")
        self.assertIn("omarchy-restart-shell", self.calls.read_text())

    def test_uninstall_can_skip_the_restart(self):
        self.run_script("some.plug", BARBARIAN_UNINSTALL_NO_RESTART="1")
        self.assertNotIn("omarchy-restart-shell", self.calls.read_text())
        self.assertFalse((self.home / ".local/state/omarchy/barbarian-restart-owed").exists())

    def test_a_refused_restart_leaves_the_stamp_install_sh_owes(self):
        self.stub("omarchy-restart-shell", "exit 1")
        result = self.run_script("some.plug")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".local/state/omarchy/barbarian-restart-owed").exists())

    def test_the_screen_being_locked_touches_nothing(self):
        self.stub("omarchy-shell", 'if [ "$1" = "lock" ]; then echo \'{"sessionLocked":true}\'; fi')
        result = self.run_script("some.plug")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.plugins / "some.plug" / "manifest.json").exists())
        self.assertNotIn("omarchy-restart-shell", self.calls.read_text())

    def test_a_folder_without_a_manifest_is_not_an_installed_plugin(self):
        result = self.run_script("not.a.plugin")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.plugins / "not.a.plugin").exists())

    def test_an_unknown_id_is_refused(self):
        result = self.run_script("nobody.here")
        self.assertNotEqual(result.returncode, 0)

    def test_an_id_with_a_slash_is_refused(self):
        result = self.run_script("../plugins/other.plug")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.plugins / "other.plug" / "manifest.json").exists())

    def test_barbarian_refuses_to_uninstall_itself(self):
        result = self.run_script("tinkerbell.arrange")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.plugins / "tinkerbell.arrange" / "manifest.json").exists())


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main()
