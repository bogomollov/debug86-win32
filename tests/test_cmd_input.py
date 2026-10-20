import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestInputCommand(unittest.TestCase):
    """Tests for the 'I' (Input from Port) command."""

    def test_input_from_port(self):
        """'I port' reads byte from simulated 64 KB port space."""
        cmds = [
            "o 3F8 A5",
            "i 3F8",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("A5", res.stdout)

    def test_input_port_boundary_ffff(self):
        """Port 0FFFFh read and write."""
        cmds = [
            "o FFFF 7C",
            "i FFFF",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("7C", res.stdout)

    def test_input_trailing_garbage(self):
        """Trailing tokens after port number trigger ^ Error."""
        cmds = [
            "i 80 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_input_missing_argument(self):
        """Missing port argument triggers ^ Error."""
        cmds = [
            "i",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
