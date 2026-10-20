import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestProceedCommand(unittest.TestCase):
    """Tests for the 'P' (Proceed / Step Over) command."""

    def test_proceed_steps_over_call(self):
        """'P' steps over near CALL instruction directly to following instruction."""
        cmds = [
            "a 100",
            "call 0108",
            "mov bx, 1111",
            "int 20",
            "mov ax, 4321",
            "ret",
            "",
            "p =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Should stop after returning from CALL: IP=0103, AX=4321, BX=0000
        self.assertIn("IP=0103", res.stdout)
        self.assertIn("AX=4321", res.stdout)
        self.assertIn("BX=0000", res.stdout)

    def test_proceed_steps_over_loop(self):
        """'P' steps over entire LOOP instruction until CX=0."""
        cmds = [
            "a 100",
            "mov cx, 0005",
            "inc ax",
            "loop 0103",
            "int 20",
            "",
            "t =100",  # Execute mov cx, 5 -> IP=0103
            "t",       # Execute inc ax -> IP=0104
            "p",       # Step over LOOP at 0104
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Loop completes: AX=0005, CX=0000, IP=0106 (int 20)
        self.assertIn("AX=0005", res.stdout)
        self.assertIn("CX=0000", res.stdout)
        self.assertIn("IP=0106", res.stdout)

    def test_proceed_steps_over_rep_string(self):
        """'P' steps over repeated string instruction until completion."""
        cmds = [
            "e 100 01 02 03 04",
            "a 110",
            "mov si, 0100",
            "mov di, 0200",
            "mov cx, 0004",
            "cld",
            "rep movsb",
            "int 20",
            "",
            "t =110 4",  # setup registers and cld, points to rep movsb at 011A
            "p",        # step over rep movsb
            "d 200 203",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("CX=0000", res.stdout)
        self.assertIn("01 02 03 04", res.stdout)

    def test_proceed_fallback_on_normal_instruction(self):
        """'P' on a normal instruction (e.g. MOV) falls back to single step."""
        cmds = [
            "a 100",
            "mov ax, 1234",
            "mov bx, 5678",
            "int 20",
            "",
            "p =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Single stepped 1 instruction: IP=0103, AX=1234, BX=0000
        self.assertIn("IP=0103", res.stdout)
        self.assertIn("AX=1234", res.stdout)
        self.assertIn("BX=0000", res.stdout)

    def test_proceed_count_zero_rejected(self):
        """A count of zero in 'P' command triggers ^ Error."""
        cmds = [
            "p =100 0",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_proceed_trailing_garbage(self):
        """Trailing tokens after proceed count trigger ^ Error."""
        cmds = [
            "p =100 2 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
