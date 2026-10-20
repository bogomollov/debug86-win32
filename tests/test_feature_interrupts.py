import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestFeatureInterrupts(unittest.TestCase):
    """Tests for simulated DOS and BIOS software interrupts."""

    def test_int20_program_terminate(self):
        """INT 20h terminates execution and emits 'Program terminated normally'."""
        cmds = [
            "a 100",
            "int 20",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Program terminated normally", res.stdout)

    def test_int21_ah4c_exit(self):
        """INT 21h AH=4Ch terminates execution and emits 'Program terminated normally'."""
        cmds = [
            "a 100",
            "mov ah, 4c",
            "int 21",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Program terminated normally", res.stdout)

    def test_int21_ah00_terminate(self):
        """INT 21h AH=00h terminates process identically to INT 20h."""
        cmds = [
            "a 100",
            "mov ah, 00",
            "int 21",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Program terminated normally", res.stdout)

    def test_int21_ah02_character_output(self):
        """INT 21h AH=02h writes single character in DL to console."""
        cmds = [
            "a 100",
            "mov ah, 02",
            "mov dl, 58",  # ASCII 'X'
            "int 21",
            "int 20",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("X", res.stdout)
        self.assertIn("Program terminated normally", res.stdout)

    def test_int21_ah09_string_output(self):
        """INT 21h AH=09h writes '$'-terminated string from DS:DX to console."""
        cmds = [
            "a 100",
            "mov ah, 09",
            "mov dx, 0109",
            "int 21",
            "int 20",
            "db 'AUTHENTIC DOS$'",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AUTHENTIC DOS", res.stdout)
        self.assertIn("Program terminated normally", res.stdout)

    def test_int21_ah30_get_dos_version(self):
        """INT 21h AH=30h returns AX=0002h (DOS version 2.0)."""
        cmds = [
            "a 100",
            "mov ah, 30",
            "int 21",
            "int 20",
            "",
            "t =100",  # mov ah, 30
            "t",       # int 21
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("AX=0002", res.stdout)

    def test_int21_ah25_ah35_interrupt_vector_table(self):
        """INT 21h AH=25h and AH=35h set and retrieve interrupt vectors in IVT."""
        cmds = [
            "a 100",
            "mov ax, 2560",  # set vector 60h
            "mov dx, 1234",  # offset
            "int 21",
            "mov ax, 3560",  # get vector 60h
            "int 21",
            "int 20",
            "",
            "t =100 5",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Vector retrieved into ES:BX
        self.assertIn("BX=1234", res.stdout)
        self.assertIn("ES=0958", res.stdout)

    def test_near_ret_program_exit(self):
        """Clean program exit via near RET jumping to PSP:0000h (INT 20h)."""
        cmds = [
            "a 100",
            "mov ax, 1234",
            "ret",
            "",
            "g =100",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("Program terminated normally", res.stdout)


if __name__ == "__main__":
    unittest.main()
