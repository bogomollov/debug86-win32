import re
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestAssembleCommand(unittest.TestCase):
    """Tests for the 'A' (Assemble) command."""

    def test_assemble_simple_instruction(self):
        """Assembling basic instructions and verifying via dump/unasm."""
        cmds = [
            "a 100",
            "mov ax, 1234",
            "nop",
            "ret",
            "",
            "u 100 L 5",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("MOV AX,1234", norm)
        self.assertIn("NOP", norm)
        self.assertIn("RET", norm)

    def test_assemble_db_directive(self):
        """Assembling raw bytes and strings with DB."""
        cmds = [
            "a 100",
            "db 11, 22, 33",
            "db \"TEST\", '$'",
            "",
            "d 100 107",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # 11 22 33 and TEST$ (54 45 53 54 24)
        self.assertIn("11 22 33 54 45 53 54 24", res.stdout)

    def test_assemble_dw_directive(self):
        """Assembling words with DW in little-endian order."""
        cmds = [
            "a 100",
            "dw 1234, 5678",
            "",
            "d 100 103",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # 1234h -> 34 12, 5678h -> 78 56
        self.assertIn("34 12 78 56", res.stdout)

    def test_assemble_size_specifiers(self):
        """Assembling memory instructions with BYTE PTR and WORD PTR."""
        cmds = [
            "a 100",
            "mov byte ptr [120], 55",
            "mov word ptr [122], 1234",
            "",
            "u 100 L 9",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("BYTE PTR [0120],55", norm)
        self.assertIn("WORD PTR [0122],1234", norm)

    def test_assemble_jumps_and_relative_offsets(self):
        """Assembling relative jumps with absolute target addresses."""
        cmds = [
            "a 100",
            "nop",
            "jnz 0100",
            "loop 0100",
            "",
            "u 100 L 5",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("JNZ 0100", norm)
        self.assertIn("LOOP 0100", norm)

    def test_assemble_default_address(self):
        """Bare 'A' command defaults to CS:0100 initially."""
        cmds = [
            "a",
            "nop",
            "",
            "u 100 L 1",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0958:0100 90", res.stdout)
        self.assertIn("NOP", res.stdout)

    def test_assemble_syntax_error_caret_and_reprompt(self):
        """Syntax error in assembler displays ^ Error and prompts for same address."""
        cmds = [
            "a 100",
            "badmnemonic",
            "nop",
            "",
            "u 100 L 1",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)
        # NOP was assembled successfully after the reprompt
        self.assertIn("0958:0100 90", res.stdout)
        self.assertIn("NOP", res.stdout)

    def test_assemble_trailing_garbage_rejection(self):
        """Trailing tokens after address in 'A' command trigger ^ Error."""
        cmds = [
            "a 100 extra",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)


    def test_assemble_far_and_near_call_jmp(self):
        """Assembling Near and Far variants of CALL and JMP."""
        cmds = [
            "a 100",
            "call 1234:5678",
            "jmp 1234:5678",
            "call 0120",
            "jmp 0120",
            "jmp 0300",
            "",
            "u 100 L 14",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        norm = re.sub(r"\s+", " ", res.stdout)
        self.assertIn("CALL 1234:5678", norm)
        self.assertIn("JMP 1234:5678", norm)
        self.assertIn("CALL 0120", norm)
        self.assertIn("JMP 0120", norm)
        self.assertIn("JMP 0300", norm)

    def test_assemble_far_syntax_errors(self):
        """Far address syntax errors and colon misuse in conditional jumps."""
        cmds = [
            "a 100",
            "jnz 1234:5678",
            "call 1234:",
            "jmp 1234:",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("^ Error", res.stdout)

    def test_assemble_db_mixed_literals(self):
        """DB directive with single quotes, double quotes, and byte literals."""
        cmds = [
            "a 100",
            "db 'A', \"B\", 43, 44",
            "",
            "d 100 103",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("41 42 43 44", res.stdout)


if __name__ == "__main__":
    unittest.main()
