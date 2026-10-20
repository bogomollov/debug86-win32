import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestCompareCommand(unittest.TestCase):
    """Tests for the 'C' (Compare) command."""

    def test_compare_identical_blocks_silent(self):
        """Comparing two identical memory regions prints nothing."""
        cmds = [
            "e 100 11 22 33 44",
            "e 200 11 22 33 44",
            "c 100 103 200",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Should not have any diff lines
        self.assertNotIn("0958:010", res.stdout)
        self.assertFalse(res.has_error())

    def test_compare_differences_output_format(self):
        """Mismatched bytes are reported as SSSS:OOOO val1 val2 SSSS:OOOO."""
        cmds = [
            "e 100 10 20 30 40",
            "e 200 10 99 30 AA",
            "c 100 103 200",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0101  20  99  0958:0201", res.stdout)
        self.assertIn("0958:0103  40  AA  0958:0203", res.stdout)
        self.assertNotIn("0958:0100", res.stdout)
        self.assertNotIn("0958:0102", res.stdout)

    def test_compare_length_syntax(self):
        """Comparing memory using 'L' count syntax."""
        cmds = [
            "e 100 01 02 03",
            "e 300 01 FF 03",
            "c 100 L 3 300",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0101  02  FF  0958:0301", res.stdout)

    def test_compare_trailing_garbage(self):
        """Trailing tokens after destination address trigger ^ Error."""
        cmds = [
            "c 100 105 200 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_compare_missing_arguments(self):
        """Missing destination or range triggers ^ Error."""
        cmds = [
            "c 100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
