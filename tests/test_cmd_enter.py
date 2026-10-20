import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestEnterCommand(unittest.TestCase):
    """Tests for the 'E' (Enter / Edit) command."""

    def test_enter_batch_hex_bytes(self):
        """Batch mode writes space-separated hex bytes into memory."""
        cmds = [
            "e 100 11 22 33 44 55",
            "d 100 104",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("11 22 33 44 55", res.stdout)

    def test_enter_batch_strings(self):
        """Batch mode accepts single and double quoted strings."""
        cmds = [
            "e 100 \"HELLO\" 'WORLD'",
            "d 100 109",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # In ASCII dump, HELLOWORLD should appear
        self.assertIn("HELLOWORLD", res.stdout)

    def test_enter_batch_mixed_hex_and_strings(self):
        """Batch mode accepts mixed hex bytes, comma delimiters, and strings."""
        cmds = [
            "e 100 B8,00,4C,\"OK\",'$'",
            "d 100 105",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("B8 00 4C 4F 4B 24", res.stdout)

    def test_enter_interactive_navigation(self):
        """Interactive mode allows entering hex values, space to advance, - to go back."""
        # e 100
        # writes AA, space to advance to 101, writes BB, minus to go back to 100, writes CC, enter to exit
        # Note: in piped mode, input_bytes can send exact keystrokes
        input_data = "e 100\nAA BB-CC\r\nd 100 101\nq\n"
        res = run_debug(commands=input_data)
        self.assertEqual(res.returncode, 0)
        # Byte at 100 was AA then overwritten by CC; byte at 101 is BB
        self.assertIn("CC BB", res.stdout)

    def test_enter_unclosed_string_quote(self):
        """Unclosed string literal triggers ^ Error."""
        cmds = [
            'e 100 "unclosed',
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_enter_byte_overflow(self):
        """Hex values exceeding 8-bit (0FFh) trigger ^ Error."""
        cmds = [
            "e 100 100",  # 100h exceeds 8 bits
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_enter_missing_address(self):
        """Missing address in 'E' command triggers ^ Error."""
        cmds = [
            "e",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
