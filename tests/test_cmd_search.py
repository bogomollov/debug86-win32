import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestSearchCommand(unittest.TestCase):
    """Tests for the 'S' (Search) command."""

    def test_search_byte_sequence(self):
        """'S' finds occurrences of a hex byte sequence and outputs SSSS:OOOO."""
        cmds = [
            "e 100 00 11 22 33 00 11 22 44",
            "s 100 110 11 22",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0101", res.stdout)
        self.assertIn("0958:0105", res.stdout)

    def test_search_string(self):
        """'S' finds occurrences of a quoted string."""
        cmds = [
            'e 150 "HELLO WORLD"',
            's 100 200 "WORLD"',
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # "WORLD" starts at 150 + 6 = 156
        self.assertIn("0958:0156", res.stdout)

    def test_search_length_syntax(self):
        """'S' supports 'L' length syntax."""
        cmds = [
            "e 100 99 AA 99",
            "s 100 L 10 AA",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0101", res.stdout)

    def test_search_no_match_silent(self):
        """When pattern is not found, search prints no addresses and returns cleanly."""
        cmds = [
            "s 100 120 FF FE FD",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertNotIn("0958:01", res.stdout)
        self.assertFalse(res.has_error())

    def test_search_unclosed_quote(self):
        """Unclosed string literal triggers ^ Error."""
        cmds = [
            's 100 200 "unclosed',
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_search_missing_list(self):
        """Missing search target list triggers ^ Error."""
        cmds = [
            "s 100 200",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
