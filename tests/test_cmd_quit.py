import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestQuitCommand(unittest.TestCase):
    """Tests for the 'Q' (Quit) command."""

    def test_quit_uppercase(self):
        """'Q' exits cleanly with exit code 0."""
        res = run_debug("Q\n")
        self.assertEqual(res.returncode, 0)

    def test_quit_lowercase(self):
        """'q' exits cleanly with exit code 0."""
        res = run_debug("q\n")
        self.assertEqual(res.returncode, 0)

    def test_quit_leading_spaces(self):
        """Spaces before 'q' are ignored and exit proceeds."""
        res = run_debug("   q\n")
        self.assertEqual(res.returncode, 0)

    def test_quit_trailing_arguments_rejected(self):
        """Entering 'Q' with any trailing arguments rejects command with ^ Error and stays running."""
        cmds = [
            "q 100",  # Should be rejected with ^ Error
            "h 1 2",  # Should execute normally
            "q",      # Clean exit
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)
        self.assertIn("0003  FFFF", res.stdout)


if __name__ == "__main__":
    unittest.main()
