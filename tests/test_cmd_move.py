import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestMoveCommand(unittest.TestCase):
    """Tests for the 'M' (Move) command."""

    def test_move_disjoint_blocks(self):
        """Moving memory block to another location."""
        cmds = [
            "e 100 01 02 03 04",
            "m 100 103 200",
            "d 200 203",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("01 02 03 04", res.stdout)

    def test_move_length_syntax(self):
        """Moving memory using 'L' length syntax."""
        cmds = [
            "e 100 AA BB CC DD",
            "m 100 L 4 300",
            "d 300 303",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AA BB CC DD", res.stdout)

    def test_move_overlapping_forward(self):
        """Overlapping move where destination > source (safe reverse copy)."""
        cmds = [
            "e 100 01 02 03 04",
            "m 100 103 101",  # Shift right by 1
            "d 100 104",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Offset 100 is unchanged (01), offsets 101..104 become 01 02 03 04
        self.assertIn("01 01 02 03 04", res.stdout)

    def test_move_overlapping_backward(self):
        """Overlapping move where destination < source (safe forward copy)."""
        cmds = [
            "e 101 01 02 03 04",
            "m 101 104 100",  # Shift left by 1
            "d 100 103",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("01 02 03 04", res.stdout)

    def test_move_trailing_garbage(self):
        """Trailing tokens after move destination trigger ^ Error."""
        cmds = [
            "m 100 105 200 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_move_missing_arguments(self):
        """Missing destination address triggers ^ Error."""
        cmds = [
            "m 100 105",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
