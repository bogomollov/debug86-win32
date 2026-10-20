import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestTraceCommand(unittest.TestCase):
    """Tests for the 'T' (Trace / Step Into) command."""

    def test_trace_single_step(self):
        """'T' executes a single instruction and prints updated registers."""
        cmds = [
            "a 100",
            "mov ax, 1234",
            "mov bx, 5678",
            "int 20",
            "",
            "t =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AX=1234", res.stdout)
        self.assertIn("BX=0000", res.stdout)
        self.assertIn("IP=0103", res.stdout)

    def test_trace_count(self):
        """'T count' single-steps multiple instructions, printing state after each."""
        cmds = [
            "a 100",
            "mov ax, 0001",
            "add ax, 0002",
            "add ax, 0003",
            "int 20",
            "",
            "t =100 3",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AX=0001", res.stdout)
        self.assertIn("AX=0003", res.stdout)
        self.assertIn("AX=0006", res.stdout)

    def test_trace_rep_string_one_iteration_at_a_time(self):
        """REP string instructions are single-stepped one iteration at a time."""
        cmds = [
            "e 100 11 22",
            "a 110",
            "mov si, 0100",
            "mov di, 0200",
            "mov cx, 0002",
            "cld",
            "rep movsb",
            "int 20",
            "",
            "t =110 4",  # setup regs and cld, IP at 011A (rep movsb)
            "t",        # step 1 iteration: CX should be 0001, IP stays at 011A
            "t",        # step 2nd iteration: CX should be 0000, IP advances to 011C
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("CX=0001", res.stdout)
        self.assertIn("CX=0000", res.stdout)

    def test_trace_count_zero_rejected(self):
        """A count of zero in 'T' command triggers ^ Error."""
        cmds = [
            "t =100 0",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_trace_trailing_garbage(self):
        """Trailing tokens after trace count trigger ^ Error."""
        cmds = [
            "t =100 2 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
