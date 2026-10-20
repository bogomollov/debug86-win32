import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestHexCommand(unittest.TestCase):
    """Tests for the 'H' (Hex Arithmetic) command."""

    def test_hex_sum_and_diff(self):
        """'H' outputs 16-bit sum and difference separated by two spaces."""
        cmds = [
            "h 100 20",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0120  00E0", res.stdout)

    def test_hex_addition_wrapping(self):
        """16-bit addition wrapping at 10000h."""
        cmds = [
            "h FFFF 0002",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0001  FFFD", res.stdout)

    def test_hex_subtraction_wrapping(self):
        """16-bit subtraction wrapping into 0FFFFh range."""
        cmds = [
            "h 0005 000A",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("000F  FFFB", res.stdout)

    def test_hex_more_than_4_digits_rejected(self):
        """Hexadecimal numbers with 5 or more digits are strictly rejected with ^ Error."""
        cmds = [
            "h 10000 1",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_hex_missing_argument(self):
        """Missing second argument triggers ^ Error."""
        cmds = [
            "h 100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_hex_trailing_garbage(self):
        """Trailing tokens after two arguments trigger ^ Error."""
        cmds = [
            "h 100 200 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
