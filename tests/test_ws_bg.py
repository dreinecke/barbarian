#!/usr/bin/env python3
"""Tests for the background picker's × — bin/ws-bg-remove, bin/ws-bg-restore — and for how the
wallpaper engine treats a theme image the × has hidden.

    python3 tests/test_ws_bg.py

Every run uses a throwaway HOME with a theme called "cat" and a copy of the engine in its
workspace-backgrounds folder, where the scripts look for it. `omarchy-shell` and `hyprctl` are
stubs that only write down that they were called, so no wallpaper on the real screen changes.
Only a theme's own images are covered: trashing one of Dave's own goes through `gio trash`,
which reaches outside the throwaway HOME.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REMOVE = ROOT / "plugin/bin/ws-bg-remove"
RESTORE = ROOT / "plugin/bin/ws-bg-restore"
ENGINE = ROOT / "engine/per-workspace-wallpaper.sh"

STUB = """#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$CALLS"
{body}
"""


class Backgrounds(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home = self.tmp / "home"
        self.state = self.home / ".local/state/omarchy/current"
        self.theme_bg = self.state / "theme/backgrounds"
        self.theme_bg.mkdir(parents=True)
        (self.state / "theme.name").write_text("cat\n")
        for name in ("1-a.jpg", "2-b.jpg", "3-c.jpg"):
            (self.theme_bg / name).write_bytes(b"")
        self.own_bg = self.home / ".config/omarchy/backgrounds/cat"
        self.own_bg.mkdir(parents=True)
        self.wsbg = self.home / ".config/omarchy/workspace-backgrounds"
        self.pins = self.wsbg / "cat"
        self.pins.mkdir(parents=True)
        shutil.copy(ENGINE, self.wsbg / ENGINE.name)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.calls = self.tmp / "calls"
        self.calls.touch()
        self.stub("omarchy-shell", "exit 0")
        self.stub("hyprctl", 'echo \'{"id": 9, "name": "9"}\'')   # desk 9 on screen: no pin repaints

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(STUB.format(body=body))
        path.chmod(0o755)

    def env(self):
        return {"HOME": str(self.home), "XDG_STATE_HOME": str(self.home / ".local/state"),
                "PATH": f"{self.bin}:{os.environ['PATH']}", "CALLS": str(self.calls),
                "XDG_RUNTIME_DIR": str(self.tmp)}

    def run_script(self, script, *args):
        result = subprocess.run([str(script), *map(str, args)], capture_output=True, text=True,
                                env=self.env())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def pin(self, desk, image):
        (self.pins / f"ws{desk}.jpg").symlink_to(image)

    def hidden(self):
        path = self.pins / "hidden-images"
        return path.read_text().splitlines() if path.exists() else None

    def auto_image(self, desk):
        """What the engine paints on `desk`, through its one-shot apply mode."""
        background = self.state / "background"
        if background.is_symlink():
            background.unlink()
        self.run_script(self.wsbg / ENGINE.name, "apply", desk)
        return os.readlink(background).rsplit("/", 1)[-1] if background.is_symlink() else None

    def test_the_stubs_stand_in_for_the_real_shell(self):
        found = subprocess.run(["bash", "-c", "command -v omarchy-shell hyprctl"],
                               capture_output=True, text=True, env=self.env()).stdout.split()
        self.assertEqual(found, [str(self.bin / "omarchy-shell"), str(self.bin / "hyprctl")])

    def test_hiding_a_theme_image_names_it_and_unpins_its_desks(self):
        self.pin(2, self.theme_bg / "2-b.jpg")
        self.pin(4, self.theme_bg / "2-b.jpg")
        self.pin(5, self.theme_bg / "3-c.jpg")
        self.run_script(REMOVE, self.theme_bg / "2-b.jpg")
        self.assertEqual(self.hidden(), ["2-b.jpg"])
        self.assertTrue((self.theme_bg / "2-b.jpg").exists())
        self.assertEqual(sorted(p.name for p in self.pins.glob("ws*")), ["ws5.jpg"])

    def test_hiding_twice_names_it_once(self):
        self.run_script(REMOVE, self.theme_bg / "2-b.jpg")
        self.run_script(REMOVE, self.theme_bg / "2-b.jpg")
        self.assertEqual(self.hidden(), ["2-b.jpg"])

    def test_restore_unhides_and_pins_the_desks_again(self):
        self.pin(2, self.theme_bg / "2-b.jpg")
        self.run_script(REMOVE, self.theme_bg / "2-b.jpg")
        self.run_script(RESTORE, self.theme_bg / "2-b.jpg", 2)
        self.assertIsNone(self.hidden())
        self.assertEqual(os.readlink(self.pins / "ws2.jpg"), str(self.theme_bg / "2-b.jpg"))

    def test_restore_leaves_the_other_hidden_images_hidden(self):
        self.run_script(REMOVE, self.theme_bg / "1-a.jpg")
        self.run_script(REMOVE, self.theme_bg / "2-b.jpg")
        self.run_script(RESTORE, self.theme_bg / "2-b.jpg")
        self.assertEqual(self.hidden(), ["1-a.jpg"])

    def test_an_image_outside_the_theme_is_refused(self):
        stray = self.tmp / "stray.jpg"
        stray.write_bytes(b"")
        result = subprocess.run([str(REMOVE), str(stray)], capture_output=True, text=True,
                                env=self.env())
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(stray.exists())
        self.assertIsNone(self.hidden())

    def test_hiding_works_when_the_theme_folder_is_a_link(self):
        # Omarchy before the copied theme folder: current/theme links to themes/<name>.
        real = self.home / ".config/omarchy/themes/cat"
        real.parent.mkdir(parents=True)
        shutil.move(str(self.state / "theme"), str(real))
        (self.state / "theme").symlink_to(real)
        self.run_script(REMOVE, real / "backgrounds/2-b.jpg")
        self.assertEqual(self.hidden(), ["2-b.jpg"])

    def test_an_auto_desk_on_a_hidden_image_takes_the_next_and_no_other_desk_moves(self):
        self.assertEqual([self.auto_image(n) for n in (1, 2, 3)], ["1-a.jpg", "2-b.jpg", "3-c.jpg"])
        self.run_script(REMOVE, self.theme_bg / "1-a.jpg")
        self.assertEqual([self.auto_image(n) for n in (1, 2, 3)], ["2-b.jpg", "2-b.jpg", "3-c.jpg"])

    def test_the_last_image_hidden_wraps_to_the_first(self):
        self.run_script(REMOVE, self.theme_bg / "3-c.jpg")
        self.assertEqual(self.auto_image(3), "1-a.jpg")

    def test_with_every_image_hidden_the_engine_paints_nothing(self):
        for name in ("1-a.jpg", "2-b.jpg", "3-c.jpg"):
            self.run_script(REMOVE, self.theme_bg / name)
        self.assertIsNone(self.auto_image(1))

    def test_dave_s_own_image_is_not_hidden_by_a_theme_image_of_the_same_name(self):
        (self.own_bg / "1-a.jpg").write_bytes(b"")
        self.run_script(REMOVE, self.theme_bg / "1-a.jpg")
        # The list is Dave's own first, then the theme's: own/1-a, 1-a, 2-b, 3-c.
        self.assertEqual(self.auto_image(1), "1-a.jpg")
        self.assertEqual(os.readlink(self.state / "background"), str(self.own_bg / "1-a.jpg"))
        self.assertEqual(self.auto_image(2), "2-b.jpg")


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main()
