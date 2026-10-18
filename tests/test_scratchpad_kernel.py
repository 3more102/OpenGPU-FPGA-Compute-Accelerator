"""Source-to-model regression for the Phase 11 memory transfer kernel."""
import unittest
from pathlib import Path

from sim.reference import Warp
from tools.opengpu_asm import assemble, disassemble

ROOT = Path(__file__).resolve().parents[1]


class TestScratchpadKernel(unittest.TestCase):
    def test_assembled_kernel_and_masked_lane_memory(self):
        source = (ROOT / "examples" / "vector_add7.ogasm").read_text(encoding="utf-8")
        words = assemble(source, max_words=16)
        self.assertEqual(words, [
            0x06010000, 0x087F0007, 0x08018001, 0x0A010001,
        ])
        self.assertEqual(disassemble(words), [
            "LOAD r3, [r0 + 0]", "ADDI r4, r3, 7",
            "STORE r4, [r0 + 1]", "LOAD r5, [r0 + 1]",
        ])
        warp = Warp(lanes=8)
        for lane in range(8):
            warp.memory[lane][0] = lane * 17 + 5
            warp.memory[lane][1] = 0xBEEF0300 + lane

        traces = warp.run_program(words, mask=0x55)
        self.assertEqual(len(traces), 4)
        self.assertEqual(traces[0], [lane * 17 + 5 if lane % 2 == 0 else 0
                                      for lane in range(8)])
        self.assertEqual(traces[1], [lane * 17 + 12 if lane % 2 == 0 else 0
                                      for lane in range(8)])
        self.assertEqual(traces[2], [0] * 8)
        self.assertEqual(traces[3], traces[1])
        for lane in range(8):
            self.assertEqual(warp.memory[lane][0], lane * 17 + 5)
            self.assertEqual(warp.memory[lane][1],
                             lane * 17 + 12 if lane % 2 == 0 else 0xBEEF0300 + lane)
            self.assertEqual(warp.regs[lane][5],
                             lane * 17 + 12 if lane % 2 == 0 else 0)


if __name__ == "__main__":
    unittest.main()
