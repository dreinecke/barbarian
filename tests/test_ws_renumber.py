#!/usr/bin/env python3
"""Tests for plugin/bin/ws-renumber's plan and the files it moves itself.

The live half (change_id, the reloads, the renames) needs a Hyprland; it was run against a nested
one. These cover the arithmetic and the files, which need nothing:

    python3 tests/test_ws_renumber.py
"""
import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "plugin/bin/ws-renumber"
# Loading the script as a module must not leave a __pycache__ inside the plugin folder, which
# install.sh would not copy and git would show.
sys.dont_write_bytecode = True


def load(tmp):
    os.environ["WS_RENUMBER_BACKGROUNDS"] = str(tmp / "bg")
    os.environ["WS_RENUMBER_LAYOUTS"] = str(tmp / "layouts")
    os.environ["WS_RENUMBER_HOOKS"] = str(tmp / "hooks")
    loader = importlib.machinery.SourceFileLoader("ws_renumber", str(SCRIPT))
    spec = importlib.util.spec_from_loader("ws_renumber", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    module.LOG = tmp / "log"
    return module


class Plan(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.m = load(self.tmp)

    def test_reorder_permutes_the_same_numbers(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("1,3,2,4", [])
        self.assertEqual(new_of, {1: 1, 3: 2, 2: 3, 4: 4})
        self.assertEqual(moves, {3: 2, 2: 3})
        self.assertEqual(deletes, {})

    def test_delete_closes_the_numbers_up(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("1,2,4,5", ["3:2"])
        self.assertEqual(new_of, {1: 1, 2: 2, 4: 3, 5: 4})
        self.assertEqual(moves, {4: 3, 5: 4})
        # Desk 3's windows went to desk 2, which keeps its number.
        self.assertEqual(deletes, {3: 2})

    def test_deleted_desks_windows_follow_their_desk_to_its_new_number(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("4,1,2", ["3:4"])
        self.assertEqual(new_of, {4: 1, 1: 2, 2: 3})
        self.assertEqual(deletes, {3: 1})

    def test_gaps_in_the_numbers_are_kept(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("5,1,3", [])
        self.assertEqual(new_of, {5: 1, 1: 3, 3: 5})

    def test_refuses_a_plan_that_makes_no_sense(self):
        for order, dels in [("", []), ("1,2,2", []), ("1,2", ["2:1"]), ("1,2", ["3:4"]), ("0,1", [])]:
            with self.assertRaises(self.m.Failure, msg=f"{order} {dels}"):
                self.m.parse_plan(order, dels)

    def test_a_new_desk_at_the_end_keeps_its_number_and_moves_nothing(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("1,2,3,4", [], ["4:Hazel"])
        self.assertEqual(new_of, {1: 1, 2: 2, 3: 3, 4: 4})
        self.assertEqual(moves, {})
        self.assertEqual(adds, {4: "Hazel"})

    def test_a_new_desk_first_takes_1_and_the_rest_move_up(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("4,1,2,3", [], ["4:"])
        self.assertEqual(moves, {1: 2, 2: 3, 3: 4})
        self.assertEqual(adds, {1: ""})

    def test_a_new_desk_skips_a_number_another_workspace_has(self):
        # Desks 1–5 with a second screen's workspace on 6: the panel names the new desk 7.
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("7,1,2,3,4,5", [], ["7:New"])
        self.assertEqual(moves, {1: 2, 2: 3, 3: 4, 4: 5, 5: 7})
        self.assertEqual(adds, {1: "New"})

    def test_a_new_desk_beside_a_deleted_one_closes_the_numbers_up(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("1,2,4,5,6", ["3:2"], ["6:New"])
        self.assertEqual(moves, {4: 3, 5: 4})
        self.assertEqual(deletes, {3: 2})
        self.assertEqual(adds, {5: "New"})

    def test_a_name_with_a_colon_survives(self):
        self.assertEqual(self.m.parse_plan("1,2", [], ["2:Mail: work"])[5], {2: "Mail: work"})

    def test_refuses_a_new_desk_plan_that_makes_no_sense(self):
        for order, dels, adds in [("1,2", [], ["3:X"]),         # not in the order
                                  ("1,3", ["2:3"], ["3:X"]),    # windows sent to a desk not made yet
                                  ("3", [], ["3:X"]),           # no existing desk stays
                                  ("1,3", [], ["3:X", "3:Y"]),  # named twice
                                  ("1,3", [], ["x:Y"])]:
            with self.assertRaises(self.m.Failure, msg=f"{order} {dels} {adds}"):
                self.m.parse_plan(order, dels, adds)

    def test_the_hooks_hear_of_a_new_desk_with_its_final_number(self):
        self.assertEqual(self.m.hook_args({1: 2}, {}, {1: "New", 3: ""}),
                         ["move:1:2", "add:1:New", "add:3"])


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.m = load(self.tmp)
        self.bg = self.tmp / "bg"
        for theme, pins in {"alpha": {1: "a", 2: "b", 3: "c"}, "beta": {3: "z"}}.items():
            (self.bg / theme).mkdir(parents=True)
            for n, target in pins.items():
                os.symlink(f"/images/{target}.png", self.bg / theme / f"ws{n}.png")
        (self.bg / "solids").mkdir()
        (self.bg / "solids" / "ws1.png").write_text("not a pin")
        self.layouts = self.tmp / "layouts"
        self.layouts.mkdir()
        (self.layouts / "2.lua").write_text('hl.workspace_rule({ workspace = "2", layout = "scrolling" })\n')

    def pins(self, theme):
        return {p.name: os.readlink(p) for p in sorted((self.bg / theme).iterdir())}

    def test_pins_swap_in_every_theme(self):
        self.m.renumber_pins({2: 3, 3: 2}, {})
        self.assertEqual(self.pins("alpha"), {"ws1.png": "/images/a.png", "ws2.png": "/images/c.png",
                                              "ws3.png": "/images/b.png"})
        self.assertEqual(self.pins("beta"), {"ws2.png": "/images/z.png"})
        self.assertTrue((self.bg / "solids" / "ws1.png").exists())

    def test_deleted_desks_pins_go(self):
        self.m.renumber_pins({3: 2}, {2: 1})
        self.assertEqual(self.pins("alpha"), {"ws1.png": "/images/a.png", "ws2.png": "/images/c.png"})

    def test_auto_image_travels_with_the_desk(self):
        new_of = {1: 1, 3: 2, 2: 3}
        self.m.renumber_auto_index(new_of, {3: 2, 2: 3}, {})
        text = (self.bg / "auto-index").read_text()
        self.assertIn("2 3\n", text)
        self.assertIn("3 2\n", text)
        # Swapping back leaves every desk on its own image, and the file goes.
        self.m.renumber_auto_index({1: 1, 3: 2, 2: 3}, {3: 2, 2: 3}, {})
        self.assertFalse((self.bg / "auto-index").exists())

    def test_a_new_desk_put_first_takes_an_image_no_other_desk_has(self):
        order, merges, new_of, moves, deletes, adds = self.m.parse_plan("4,1,2,3", [], ["4:"])
        self.m.renumber_auto_index(new_of, moves, deletes)
        index = (self.bg / "auto-index").read_text()
        # The new desk 1 shows the theme's 4th image; desks 1–3, now 2–4, keep theirs.
        for line in ("1 4\n", "2 1\n", "3 2\n", "4 3\n"):
            self.assertIn(line, index)

    def test_layout_rule_moves_with_its_desk(self):
        self.m.renumber_layouts({2: 4, 4: 2}, {})
        self.assertFalse((self.layouts / "2.lua").exists())
        self.assertEqual((self.layouts / "4.lua").read_text(),
                         'hl.workspace_rule({ workspace = "4", layout = "scrolling" })\n')


if __name__ == "__main__":
    unittest.main()
