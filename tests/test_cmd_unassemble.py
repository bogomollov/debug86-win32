import re
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestUnassembleCommand(unittest.TestCase):
    """Tests for the 'U' (Unassemble) command."""

    def test_unassemble_basic_instructions(self):
        """'U' disassembles machine code into instruction mnemonics."""
        cmds = [
            "e 100 B8 34 12 CD 20",  # MOV AX, 1234; INT 20
            "u 100 104",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("MOV AX,1234", norm)
        self.assertIn("INT 20", norm)

    def test_unassemble_continuation(self):
        """Consecutive bare 'U' commands continue disassembling sequentially from instruction boundary."""
        cmds = [
            "u 100 L 5",
            "u",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0100", res.stdout)
        # First dump ended at 0105; next instruction boundary is 0106
        self.assertIn("0958:0106", res.stdout)

    def test_unassemble_absolute_branch_targets(self):
        """Relative jumps are displayed with absolute destination addresses."""
        cmds = [
            "e 100 75 05",  # JNZ +5 -> target 0107
            "u 100 101",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("JNZ 0107", norm)

    def test_unassemble_signed_immediate_83h(self):
        """Opcode 83h signed immediate is displayed with explicit '+' or '-' sign."""
        cmds = [
            "e 100 83 C3 05",  # ADD BX, +05
            "e 103 83 EB FE",  # SUB BX, -02 (FEh = -2)
            "u 100 105",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("ADD BX,+05", norm)
        self.assertIn("SUB BX,-02", norm)

    def test_unassemble_unknown_opcode_db_fallback(self):
        """Unrecognized opcodes are disassembled cleanly as 'DB xx'."""
        cmds = [
            "e 100 0F",  # 0F is invalid 8086 opcode
            "u 100 100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("DB 0F", norm)

    def test_unassemble_trailing_garbage(self):
        """Trailing tokens after unassemble range trigger ^ Error."""
        cmds = [
            "u 100 120 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


if __name__ == "__main__":
    unittest.main()
