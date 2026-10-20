import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestFillCommand(unittest.TestCase):
    """Tests for the 'F' (Fill) command."""

    def test_fill_single_byte_range(self):
        """Filling a range with a single byte value."""
        cmds = [
            "f 100 107 AA",
            "d 100 107",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AA AA AA AA AA AA AA AA", res.stdout)

    def test_fill_multibyte_pattern_cycling(self):
        """Filling with a multi-byte pattern repeats the pattern cyclically."""
        cmds = [
            "f 100 105 11 22 33",
            "d 100 105",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("11 22 33 11 22 33", res.stdout)

    def test_fill_string_pattern(self):
        """Filling with a quoted string pattern."""
        cmds = [
            'f 100 L 6 "AB"',
            "d 100 105",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # 'AB' repeated 3 times = 41 42 41 42 41 42
        self.assertIn("41 42 41 42 41 42", res.stdout)
        self.assertIn("ABABAB", res.stdout)

    def test_fill_length_syntax(self):
        """Filling using 'L' count syntax."""
        cmds = [
            "f 200 L 4 90",
            "d 200 203",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("90 90 90 90", res.stdout)

    def test_fill_unclosed_string_quote(self):
        """Unclosed string literal in fill triggers ^ Error."""
        cmds = [
            'f 100 110 "open',
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_fill_missing_pattern(self):
        """Missing pattern list in fill triggers ^ Error."""
        cmds = [
            "f 100 110",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
