import re
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestDumpCommand(unittest.TestCase):
    """Tests for the 'D' (Dump) command."""

    def test_dump_default_continuation(self):
        """Bare 'D' dumps 128 bytes and subsequent 'D' continues from where previous ended."""
        cmds = [
            "d 100 L 20",
            "d",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # First dump starts at 0100
        self.assertIn("0958:0100", res.stdout)
        # Continuation dump starts at 0120
        self.assertIn("0958:0120", res.stdout)

    def test_dump_row_formatting_and_hyphen(self):
        """Dump displays 16 bytes per row with a hyphen between byte 8 and 9."""
        cmds = [
            "e 100 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F",
            "d 100 10F",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Row format check: 00 01 02 03 04 05 06 07-08 09 0A 0B 0C 0D 0E 0F
        self.assertIn(
            "00 01 02 03 04 05 06 07-08 09 0A 0B 0C 0D 0E 0F",
            res.stdout,
        )

    def test_dump_ascii_printable_and_dots(self):
        """Dump ASCII column shows printable characters and dots for non-printables."""
        cmds = [
            "e 100 41 42 00 43",  # 'A', 'B', null, 'C'
            "d 100 103",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # In the ASCII section, 'AB.C' should appear
        self.assertIn("AB.C", res.stdout)

    def test_dump_length_syntax(self):
        """'D addr L count' dumps exactly the specified number of bytes."""
        cmds = [
            "d 100 L 10",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0100", res.stdout)
        # 16 bytes (1 row) dumped
        dump_rows = [line for line in res.lines if "0958:" in line]
        self.assertEqual(len(dump_rows), 1)

    def test_dump_segment_override(self):
        """Segment override can be specified in dump address."""
        cmds = [
            "d CS:0000 L 10",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0000", res.stdout)

    def test_dump_trailing_garbage(self):
        """Trailing tokens after dump range trigger ^ Error."""
        cmds = [
            "d 100 120 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
