import os
import unittest
from pathlib import Path
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import PROJECT_ROOT, run_debug


class TestWriteCommand(unittest.TestCase):
    """Tests for the 'W' (Write) command."""

    def test_write_creates_file_with_correct_bytes(self):
        """'W' writes BX:CX bytes from memory starting at CS:0100h into named file."""
        test_file = PROJECT_ROOT / "test_write_output.bin"
        if test_file.exists():
            test_file.unlink()

        try:
            cmds = [
                f"n {test_file.name}",
                "e 100 DE AD BE EF",
                "r cx",
                "4",
                "",
                "w",
                "q",
            ]
            res = run_debug(cmds)
            self.assertEqual(res.returncode, 0)
            self.assertIn("Writing 0004 bytes", res.stdout)
            self.assertTrue(test_file.exists())
            self.assertEqual(test_file.read_bytes(), b"\xDE\xAD\xBE\xEF")
        finally:
            if test_file.exists():
                test_file.unlink()

    def test_write_custom_address(self):
        """'W addr' writes BX:CX bytes starting from specified offset."""
        test_file = PROJECT_ROOT / "test_write_custom.bin"
        if test_file.exists():
            test_file.unlink()

        try:
            cmds = [
                f"n {test_file.name}",
                "e 300 11 22 33",
                "r cx",
                "3",
                "",
                "w 300",
                "q",
            ]
            res = run_debug(cmds)
            self.assertEqual(res.returncode, 0)
            self.assertIn("Writing 0003 bytes", res.stdout)
            self.assertTrue(test_file.exists())
            self.assertEqual(test_file.read_bytes(), b"\x11\x22\x33")
        finally:
            if test_file.exists():
                test_file.unlink()

    def test_write_file_creation_error_on_empty_name(self):
        """Calling 'W' without a valid filename produces 'File creation error'."""
        cmds = [
            "n",  # Clear filename
            "w",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("File creation error", res.stdout)

    def test_write_trailing_garbage(self):
        """Trailing tokens after write address trigger ^ Error."""
        cmds = [
            "w 100 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
