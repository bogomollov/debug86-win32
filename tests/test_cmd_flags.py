import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestFlagsCommand(unittest.TestCase):
    """Tests for the 'RF' / 'R F' (Register Flags) command."""

    def test_rf_display_and_prompt(self):
        """'RF' displays current flags followed by '- ' prompt."""
        res = run_debug("rf\n\nq\n")
        self.assertEqual(res.returncode, 0)
        self.assertIn("NV UP EI PL NZ NA PO NC - ", res.stdout)

    def test_rf_modify_single_flag(self):
        """Modifying a flag updates its state in register dump."""
        cmds = [
            "rf",
            "cy",  # Set carry
            "r",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Register dump line should contain 'PO CY' instead of 'PO NC'
        flag_line = [line for line in res.lines if "NV UP" in line][-1]
        self.assertIn("PO CY", flag_line)
        self.assertNotIn("NC", flag_line)

    def test_rf_modify_multiple_flags(self):
        """Multiple flags can be modified in a single line."""
        cmds = [
            "rf",
            "ov dn ng zr cy",
            "r",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Should now be: OV DN EI NG ZR NA PO CY
        self.assertIn("OV DN EI NG ZR", res.stdout)

    def test_rf_bad_flag_yields_bf_error(self):
        """Unrecognized flag code yields 'BF error'."""
        cmds = [
            "rf",
            "xx",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("BF error", res.stdout)

    def test_rf_duplicate_flag_yields_df_error(self):
        """Modifying the same flag twice in a single input line yields 'DF error'."""
        cmds = [
            "rf",
            "ov nv",  # OV and NV both target Overflow flag
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("DF error", res.stdout)

    def test_rf_trailing_arguments_on_command_line(self):
        """Trailing tokens on the '-rf' command line itself trigger ^ Error."""
        cmds = [
            "rf extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
