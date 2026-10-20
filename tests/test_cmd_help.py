import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestHelpCommand(unittest.TestCase):
    """Tests for the '?' (Help) command."""

    def test_help_lists_all_commands(self):
        """'?' displays syntax templates for all debugger commands."""
        res = run_debug("?\nq\n")
        self.assertEqual(res.returncode, 0)
        expected_commands = [
            "assemble",
            "compare",
            "dump",
            "enter",
            "fill",
            "go",
            "hex",
            "input",
            "load",
            "move",
            "name",
            "output",
            "proceed",
            "quit",
            "register",
            "search",
            "trace",
            "unassemble",
            "write",
        ]
        for cmd in expected_commands:
            with self.subTest(command=cmd):
                self.assertIn(cmd, res.stdout.lower())

    def test_help_returns_to_prompt(self):
        """After displaying help, debugger returns to standard '-' prompt."""
        res = run_debug("?\nq\n")
        self.assertEqual(res.returncode, 0)
        # Check that output ends with '-' prompt before quit
        self.assertTrue(res.stdout.rstrip().endswith("-"))


if __name__ == "__main__":
    unittest.main()
