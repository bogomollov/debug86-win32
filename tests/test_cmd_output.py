import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestOutputCommand(unittest.TestCase):
    """Tests for the 'O' (Output to Port) command."""

    def test_output_and_readback(self):
        """'O port byte' writes byte to simulated I/O port space."""
        cmds = [
            "o 2F8 5A",
            "i 2F8",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("5A", res.stdout)

    def test_output_port_zero(self):
        """Writing and reading from port 0000h."""
        cmds = [
            "o 0 33",
            "i 0",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("33", res.stdout)

    def test_output_byte_value_overflow(self):
        """Byte argument exceeding 0FFh triggers ^ Error."""
        cmds = [
            "o 80 100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_output_missing_byte_argument(self):
        """Missing byte argument triggers ^ Error."""
        cmds = [
            "o 80",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_output_trailing_garbage(self):
        """Trailing tokens after byte argument trigger ^ Error."""
        cmds = [
            "o 80 FF extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
