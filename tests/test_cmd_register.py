import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestRegisterCommand(unittest.TestCase):
    """Tests for the 'R' (Register) command."""

    def test_register_dump_layout_and_format(self):
        """Bare 'R' outputs 8 general registers, 4 segment registers + IP, flags, and CS:IP disassembly."""
        res = run_debug("r\nq\n")
        self.assertEqual(res.returncode, 0)
        # Line 1: AX..DI
        self.assertIn("AX=", res.stdout)
        self.assertIn("BX=", res.stdout)
        self.assertIn("CX=", res.stdout)
        self.assertIn("DX=", res.stdout)
        self.assertIn("SP=FFEE", res.stdout)
        self.assertIn("BP=", res.stdout)
        self.assertIn("SI=", res.stdout)
        self.assertIn("DI=", res.stdout)
        # Line 2: segments, IP, and flags
        self.assertIn("DS=0958", res.stdout)
        self.assertIn("ES=0958", res.stdout)
        self.assertIn("SS=0958", res.stdout)
        self.assertIn("CS=0958", res.stdout)
        self.assertIn("IP=0100", res.stdout)
        self.assertIn("NV UP EI PL NZ NA PO NC", res.stdout)

    def test_register_live_memory_preview(self):
        """Line 3 of register dump resolves memory operands and displays effective address preview."""
        cmds = [
            "e 120 4C 00",
            "a 100",
            "mov bx, [0120]",
            "",
            "r",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Check memory operand preview on right margin: DS:0120=004C
        self.assertIn("DS:0120=004C", res.stdout)

    def test_register_edit_update_value(self):
        """'R reg' prompts with ':' and updates value when new hex is entered."""
        cmds = [
            "r ax",
            "1234",
            "r",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AX=1234", res.stdout)

    def test_register_edit_retain_value_on_empty_enter(self):
        """Pressing Enter at ':' prompt retains previous register value."""
        cmds = [
            "r bx",
            "5678",
            "r bx",
            "",      # Press enter without typing value
            "r",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("BX=5678", res.stdout)

    def test_register_bad_register_name(self):
        """Unrecognized register name yields 'BR error'."""
        cmds = [
            "r zz",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("BR error", res.stdout)

    def test_register_trailing_garbage_on_command_line(self):
        """Trailing tokens after register name trigger ^ Error."""
        cmds = [
            "r ax extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
