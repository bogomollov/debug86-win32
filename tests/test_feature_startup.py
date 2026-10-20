import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug, temporary_binary


class TestFeatureStartup(unittest.TestCase):
    """Tests for the startup command-line invocation and PSP initialization."""

    def test_startup_loads_binary_and_populates_psp(self):
        """Startup with binary argument loads target at CS:0100h and sets PSP command tail."""
        # Payload: MOV AX, 1234; INT 20
        payload = b"\xB8\x34\x12\xCD\x20"
        with temporary_binary(payload, filename="start_test.com") as bin_path:
            # Run: debug86-win32.exe start_test.com hello world
            res = run_debug(
                args=[bin_path.name, "hello", "world"],
                commands=["r", "d 0 0F", "d 80 8F", "g", "q"],
            )
            self.assertEqual(res.returncode, 0)

            # Check BX:CX = file size (5)
            self.assertIn("CX=0005", res.stdout)
            self.assertIn("BX=0000", res.stdout)
            self.assertIn("IP=0100", res.stdout)

            # Check PSP:0000h contains CD 20 (INT 20h)
            self.assertIn("0958:0000  CD 20", res.stdout)

            # Check PSP:0080h contains length and args string " hello world\r"
            self.assertIn("hello world", res.stdout)

            # Check execution
            self.assertIn("Program terminated normally", res.stdout)

    def test_startup_quoted_binary_path(self):
        """Startup handles filenames with spaces."""
        payload = b"\xB8\x00\x4C\xCD\x21"  # MOV AX, 4C00; INT 21
        with temporary_binary(payload, filename="file with spaces.com") as bin_path:
            res = run_debug(
                args=[str(bin_path)],
                commands=["g", "q"],
            )
            self.assertEqual(res.returncode, 0)
            self.assertIn("Program terminated normally", res.stdout)

    def test_startup_nonexistent_file(self):
        """Starting with a non-existent file leaves BX and CX as 0000."""
        res = run_debug(
            args=["nonexistent_startup_file.com"],
            commands=["r", "q"],
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("BX=0000", res.stdout)
        self.assertIn("CX=0000", res.stdout)


if __name__ == "__main__":
    unittest.main()
