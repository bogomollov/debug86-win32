import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from tests.helpers import run_debug


class TestFeatureMemoryAddressing(unittest.TestCase):
    """Tests for 8086 segmented real-mode memory architecture and addressing modes."""

    def test_segmented_linear_address_equivalence(self):
        """Segment:Offset translation ((Segment * 16) + Offset) yields identical physical memory location."""
        # 0958h:0100h -> linear 09680h
        # 0950h:0180h -> linear 09680h
        # 0948h:0200h -> linear 09680h
        cmds = [
            "e 0958:0100 77 88",
            "d 0950:0180 0181",
            "d 0948:0200 0201",
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0950:0180  77 88", res.stdout)
        self.assertIn("0948:0200  77 88", res.stdout)

    def test_segment_defaults_code_vs_data(self):
        """Code commands default to CS; data commands default to DS."""
        cmds = [
            # Modify DS to 0200 and CS to 0300
            "r ds",
            "0200",
            "r cs",
            "0300",
            "e 100 AA",       # Uses DS (0200:0100)
            "a 100",          # Uses CS (0300:0100)
            "nop",
            "",
            "d 0200:0100 0100",  # Verify byte written to DS:0100
            "u 0300:0100 0100",  # Verify instruction assembled to CS:0100
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        self.assertIn("0200:0100  AA", res.stdout)
        self.assertIn("0300:0100 90", res.stdout)
        self.assertIn("NOP", res.stdout)

    def test_modrm_bp_defaults_to_ss(self):
        """ModR/M addressing references involving BP default to SS segment."""
        cmds = [
            "a 100",
            "mov bp, 0200",
            "mov ax, [bp]",
            "int 20",
            "",
            "t =100",  # execute mov bp, 0200
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Next instruction preview should reference SS:0200
        self.assertIn("SS:0200=", res.stdout)

    def test_modrm_bx_defaults_to_ds(self):
        """ModR/M addressing references involving BX default to DS segment."""
        cmds = [
            "a 100",
            "mov bx, 0200",
            "mov ax, [bx]",
            "int 20",
            "",
            "t =100",  # execute mov bx, 0200
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Next instruction preview should reference DS:0200
        self.assertIn("DS:0200=", res.stdout)

    def test_modrm_segment_override_prefix(self):
        """Explicit segment prefix (e.g. ES:) overrides the default segment."""
        cmds = [
            "a 100",
            "mov bx, 0200",
            "mov ax, es:[bx]",
            "int 20",
            "",
            "t =100",  # execute mov bx, 0200
            "q",
        ]
        res = run_debug(cmds)
        self.assertEqual(res.returncode, 0)
        # Next instruction preview should reference ES:0200
        self.assertIn("ES:0200=", res.stdout)


if __name__ == "__main__":
    unittest.main()
