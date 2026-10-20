import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestNameCommand(unittest.TestCase):
    """Tests for the 'N' (Name) command."""

    def test_name_sets_filename_and_tail(self):
        """'N filename arg1 arg2' initializes the PSP command tail at CS:0080h."""
        cmds = [
            "n testfile.com foo bar",
            "d 80 8F",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # PSP:0080h has byte count (length of " foo bar" = 8), followed by " foo bar\r"
        self.assertIn("foo bar", res.stdout)

    def test_name_quoted_filename(self):
        """'N \"file with space.com\"' parses double-quoted filenames."""
        cmds = [
            'n "my file.com" opt1',
            "d 80 8F",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("opt1", res.stdout)

    def test_name_bare_clears_filename_and_tail(self):
        """Bare 'N' clears current filename and resets PSP command tail to 0."""
        cmds = [
            "n foo.com arg1",
            "n",
            "d 80 85",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Length at 0080h should be 00 and byte at 0081h should be 0D
        self.assertIn("00 0D", res.stdout)


if __name__ == "__main__":
    unittest.main()
