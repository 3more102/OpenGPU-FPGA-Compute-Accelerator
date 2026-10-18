import unittest
from pathlib import Path

from sim.reference import DEMO_PROGRAM
from tools.opengpu_asm import assemble, disassemble, disassemble_word


DEMO_SOURCE = """
ADD   r3,  r1,  r2
XOR   r4,  r1,  r2
MUL   r5,  r1,  r2
SUB   r6,  r3,  r2
STORE r5, [r8 + 0]
LOAD  r9, [r8 + 0]
ADD   r10, r9, r1
ADDI  r11, r1, 5
BNE   r1, r2, after_sentinel
ADDI  r12, r1, 99
after_sentinel:
ADD   r13, r11, r1
BNE   r1, r1, +1
"""


class TestAssembler(unittest.TestCase):
    def test_checked_in_demo_source_matches_rtl_reference_words(self):
        source_path = Path(__file__).resolve().parents[1] / "examples" / "demo.ogasm"
        self.assertEqual(assemble(source_path.read_text(encoding="utf-8")), list(DEMO_PROGRAM))

    def test_demo_assembly_matches_rtl_reference_words(self):
        self.assertEqual(assemble(DEMO_SOURCE), list(DEMO_PROGRAM))

    def test_forward_and_backward_labels(self):
        words = assemble("start: ADDI r1, r0, 1\nBNE r1, r0, start\nJUMP start\n")
        self.assertEqual(len(words), 3)
        # At PC 1, the target at PC 0 is offset 0 - (1 + 1) = -2.
        self.assertEqual(words[1] & 0xFFFF, 0xFFFE)
        # At PC 2, the same target is offset -3.
        self.assertEqual(words[2] & 0xFFFF, 0xFFFD)

    def test_signed_immediate_and_memory_offset_boundaries(self):
        words = assemble("ADDI r1, r0, -32768\nLOAD r2, [r3 - 16384]\nSTORE r4, [r5 + 16383]\n")
        self.assertEqual(words[0] & 0xFFFF, 0x8000)
        self.assertEqual(words[1] & 0x7FFF, 0x4000)
        self.assertEqual(words[2] & 0x7FFF, 0x3FFF)

    def test_disassembler_round_trip_for_demo(self):
        words = assemble(DEMO_SOURCE)
        text = "\n".join(disassemble(words)) + "\n"
        self.assertEqual(assemble(text), words)

    def test_nop_alias(self):
        self.assertEqual(assemble("NOP\n"), [0])
        self.assertEqual(disassemble_word(0), "ADD r0, r0, r0")

    def test_rejects_unknown_label_and_duplicate_label(self):
        with self.assertRaisesRegex(ValueError, "undefined"):
            assemble("BNE r1, r2, missing\n")
        with self.assertRaisesRegex(ValueError, "duplicate label"):
            assemble("again: NOP\nagain: NOP\n")

    def test_rejects_bad_register_immediate_and_program_length(self):
        with self.assertRaisesRegex(ValueError, "register index out of range"):
            assemble("ADD r16, r1, r2\n")
        with self.assertRaisesRegex(ValueError, "does not fit signed 16 bits"):
            assemble("ADDI r1, r0, 32768\n")
        with self.assertRaisesRegex(ValueError, "maximum is 1"):
            assemble("NOP\nNOP\n", max_words=1)


if __name__ == "__main__":
    unittest.main()
