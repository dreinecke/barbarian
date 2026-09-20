#!/usr/bin/env python3
"""Tests for plugin/bin/bar-arrange-apply — the one thing that writes the bar's layout.

    python3 tests/test_bar_arrange_apply.py

Each test runs the real script with HOME pointing at a throwaway folder, so nothing touches the
running bar.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "plugin/bin/bar-arrange-apply"

STOCK = {"bar": {"layout": {
    "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}],
    "center": [],
    "right": [{"id": "omarchy.clock", "format": "ddd d MMM HH:mm"}, {"id": "omarchy.power"},
              {"id": "tinkerbell.arrange"}],
}}}


class Apply(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        (self.home / ".config/omarchy").mkdir(parents=True)
        self.shell = self.home / ".config/omarchy/shell.json"
        self.hidden = self.home / ".config/omarchy/bar-hidden.json"
        self.write(STOCK)

    def write(self, layout, hidden=None):
        self.shell.write_text(json.dumps(layout, indent=2) + "\n")
        self.hidden.write_text(json.dumps(hidden or {"left": [], "center": [], "right": []}) + "\n")

    def run_apply(self, *args):
        result = subprocess.run([str(SCRIPT), *args], capture_output=True, text=True,
                                env={**os.environ, "HOME": str(self.home)})
        return result

    def layout(self):
        return json.loads(self.shell.read_text())["bar"]["layout"]

    def ids(self, lane):
        return [entry["id"] for entry in self.layout()[lane]]

    def parked(self):
        return json.loads(self.hidden.read_text())

    def test_a_strip_that_is_not_changing_lane_stays_where_it_stands(self):
        """A stock bar's menu button must not be pushed out of the corner by a desk change."""
        self.run_apply("R:omarchy.power", "R:omarchy.clock", "WS:omarchy.workspaces:left")
        self.assertEqual(self.ids("left"), ["omarchy.menu", "omarchy.workspaces"])
        self.assertEqual(self.ids("right")[:2], ["omarchy.power", "omarchy.clock"])

    def test_a_strip_changing_lane_leads_its_new_one(self):
        self.run_apply("R:omarchy.clock", "R:omarchy.power", "WS:omarchy.workspaces:center")
        self.assertEqual(self.ids("left"), ["omarchy.menu"])
        self.assertEqual(self.ids("center"), ["omarchy.workspaces"])

    def test_entries_travel_whole(self):
        self.run_apply("R:omarchy.power", "R:omarchy.clock", "WS:omarchy.workspaces:left")
        clock = [e for e in self.layout()["right"] if e["id"] == "omarchy.clock"][0]
        self.assertEqual(clock["format"], "ddd d MMM HH:mm")

    def test_hiding_parks_the_whole_entry_and_showing_brings_it_back(self):
        self.run_apply("R:omarchy.clock:hidden", "R:omarchy.power", "WS:omarchy.workspaces:left")
        self.assertNotIn("omarchy.clock", self.ids("right"))
        parked = self.parked()["right"]
        self.assertEqual(parked[0]["entry"]["format"], "ddd d MMM HH:mm")
        self.run_apply("R:omarchy.clock", "R:omarchy.power", "WS:omarchy.workspaces:left")
        self.assertEqual(self.ids("right")[:2], ["omarchy.clock", "omarchy.power"])
        self.assertEqual(self.parked()["right"], [])

    def test_an_id_it_does_not_recognise_changes_nothing(self):
        before = self.shell.read_text()
        result = self.run_apply("R:omarchy.clock", "R:nobody.here")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.shell.read_text(), before)

    def test_the_panel_never_drops_an_entry_it_does_not_list(self):
        """Barbarian's own widget is never listed; it must keep its place at the lane's end."""
        self.run_apply("R:omarchy.power", "R:omarchy.clock", "WS:omarchy.workspaces:left")
        self.assertIn("tinkerbell.arrange", self.ids("right"))


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    unittest.main()
