import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestGoCommand(unittest.TestCase):
    """Tests for the 'G' (Go) command."""

    def test_go_until_normal_termination(self):
        """'G' runs execution until INT 20h or INT 21h AH=4Ch."""
        cmds = [
            "a 100",
            "mov ax, 4C00",
            "int 21",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Program terminated normally", res.stdout)

    def test_go_with_single_breakpoint(self):
        """'G bp' stops silently at breakpoint and prints register dump."""
        cmds = [
            "a 100",
            "mov ax, 1111",
            "mov bx, 2222",
            "mov cx, 3333",
            "int 20",
            "",
            "g =100 0106",  # 0106 is address of 'mov cx, 3333'
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Should stop before mov cx: AX=1111, BX=2222, CX=0000, IP=0106
        self.assertIn("AX=1111", res.stdout)
        self.assertIn("BX=2222", res.stdout)
        self.assertIn("CX=0000", res.stdout)
        self.assertIn("IP=0106", res.stdout)
        # Authentic debug has no synthetic "Breakpoint reached" banner
        self.assertNotIn("Breakpoint reached", res.stdout)

    def test_go_with_multiple_breakpoints(self):
        """'G' with multiple breakpoints halts at the first encountered."""
        cmds = [
            "a 100",
            "mov ax, 1000",
            "jmp 0109",
            "mov ax, 2000",
            "mov bx, 3000",
            "int 20",
            "",
            "g =100 0106 0109",  # 0106 is skipped by jmp; 0109 is hit
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("IP=0109", res.stdout)
        self.assertIn("AX=1000", res.stdout)

    def test_go_breakpoint_limit_exceeded(self):
        """Specifying more than 10 breakpoints produces 'BP error'."""
        cmds = [
            "g 100 102 104 106 108 10A 10C 10E 110 112 114",  # 11 breakpoints
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("BP error", res.stdout)

    def test_go_exactly_ten_breakpoints_allowed(self):
        """Specifying exactly 10 breakpoints is valid and does not produce 'BP error'."""
        cmds = [
            "a 100",
            "int 20",
            "",
            "g =100 110 112 114 116 118 11A 11C 11E 120 122",  # 10 breakpoints
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertNotIn("BP error", res.stdout)
        self.assertIn("Program terminated normally", res.stdout)

    def test_go_invalid_syntax(self):
        """Invalid characters in go command trigger ^ Error."""
        cmds = [
            "g =zzzz",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
