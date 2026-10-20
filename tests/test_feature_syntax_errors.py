import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestFeatureSyntaxErrors(unittest.TestCase):
    """Tests for authentic MS-DOS DEBUG syntax error formatting, alignment, and rules."""

    def test_dynamic_column_caret_alignment(self):
        """The '^ Error' message dynamically aligns under the invalid token."""
        # -d 100 200 zz
        # '-' is 1 char prompt. "d 100 200 " is 10 chars.
        # So '^' should be at column index 11 (0-indexed).
        res = run_debug("d 100 200 zz\nq\n")
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)
        # Find error line
        error_line = [l for l in res.lines if "^ Error" in l][0]
        caret_pos = error_line.index("^")
        # In "-           ^ Error", caret_pos should be 12 (1 prompt char '-' + 11 spaces)
        self.assertEqual(caret_pos, 12)

    def test_tab_stop_column_expansion(self):
        """Tab stops (ASCII 9) expand to 8-character boundaries in column calculation."""
        res = run_debug("d\tzz\nq\n")
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)
        error_line = [l for l in res.lines if "^ Error" in l][0]
        caret_pos = error_line.index("^")
        # 'd' at col 0, tab advances to col 8 -> with prompt '-', caret at col 9
        self.assertEqual(caret_pos, 9)

    def test_hex_limit_4_digits(self):
        """Hex values exceeding 4 digits (16-bit range) are rejected with ^ Error."""
        res = run_debug("d 10000\nq\n")
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_case_insensitivity(self):
        """Commands and hexadecimal arguments are completely case-insensitive."""
        res_lower = run_debug("h a b\nq\n")
        res_upper = run_debug("H A B\nq\n")
        self.assertEqual(res_lower.returncode, 0)
        self.assertEqual(res_upper.returncode, 0)
        self.assertIn("0015  FFFF", res_lower.stdout)
        self.assertIn("0015  FFFF", res_upper.stdout)

    def test_delimiter_interchangeability_and_collapsing(self):
        """Commas, spaces, and tabs are interchangeable delimiters and collapse."""
        cmds = [
            "e,100,,11,,,22",
            "d,100,101",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("11 22", res.stdout)
        self.assertFalse(res.has_error())

    def test_empty_line_prints_prompt(self):
        """Pressing Enter on an empty line prints another '-' prompt."""
        res = run_debug("\n\nq\n")
        self.assertEqual(res.returncode, 0)
        # Sequence of prompts
        self.assertIn("---", res.stdout.replace("\r", "").replace("\n", ""))


if __name__ == "__main__":
    unittest.main()
