import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug, temporary_binary


class TestLoadCommand(unittest.TestCase):
    """Tests for the 'L' (Load) command."""

    def test_load_file_sets_bxcx_and_resets_cpu(self):
        """Loading a file at CS:0100h populates BX:CX and resets CPU registers."""
        # 5 bytes dummy payload: MOV AX, 1234; INT 20
        payload = b"\xB8\x34\x12\xCD\x20"
        with temporary_binary(payload, filename="test_load.com") as bin_path:
            cmds = [
                f"n {bin_path.name}",
                "l",
                "r",
                "d 100 104",
                "q",
            ]
            res = run_debug(cmds)
            self.assertEqual(res.returncode, 0)
            self.assertIn("CX=0005", res.stdout)
            self.assertIn("BX=0000", res.stdout)
            self.assertIn("IP=0100", res.stdout)
            self.assertIn("SP=FFEE", res.stdout)
            self.assertIn("B8 34 12 CD 20", res.stdout)

    def test_load_explicit_address(self):
        """Loading a file at a custom address offset."""
        payload = b"\x11\x22\x33\x44"
        with temporary_binary(payload, filename="test_load2.com") as bin_path:
            cmds = [
                f"n {bin_path.name}",
                "l 200",
                "d 200 203",
                "q",
            ]
            res = run_debug(cmds)
            self.assertEqual(res.returncode, 0)
            self.assertIn("11 22 33 44", res.stdout)

    def test_load_file_not_found(self):
        """Loading a non-existent file produces 'File not found'."""
        cmds = [
            "n nonexistent_file_xyz.bin",
            "l",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("File not found", res.stdout)

    def test_load_no_filename_set(self):
        """Calling 'L' without setting a filename first outputs 'File not found'."""
        cmds = [
            "n",  # ensure cleared
            "l",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("File not found", res.stdout)

    def test_load_trailing_garbage(self):
        """Trailing tokens after load address trigger ^ Error."""
        cmds = [
            "l 100 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
