import random
import unittest
from sim.reference import (
    DEMO_PROGRAM, Warp, alu, encode, encode_branch, encode_imm, MASK32,
)


class TestReference(unittest.TestCase):
    def test_ops(self):
        for op in range(8):
            for a, b in [(0, 0), (1, 1), (MASK32, 2), (0x80000000, 31)]:
                self.assertTrue(0 <= alu(op, a, b) <= MASK32)
        self.assertEqual(alu(0, MASK32, 1), 0)
        self.assertEqual(alu(1, 0, 1), MASK32)
        self.assertEqual(alu(6, 0x80000000, 1), 0x40000000)

    def test_mask_and_r0(self):
        w = Warp()
        for i in range(8):
            w.regs[i][1] = i + 1
            w.regs[i][2] = 10
        out = w.step(encode(0, 3, 1, 2), 0b01010101)
        self.assertEqual(out, [11, 0, 13, 0, 15, 0, 17, 0])
        self.assertEqual([r[3] for r in w.regs], out)
        w.step(encode(0, 0, 1, 2), 255)
        self.assertEqual([r[0] for r in w.regs], [0] * 8)

    def test_randomized(self):
        rng = random.Random(7)
        w = Warp()
        for _ in range(1000):
            op, rd, rs1, rs2 = (rng.randrange(8), rng.randrange(16),
                                rng.randrange(16), rng.randrange(16))
            mask = rng.randrange(256)
            before = [r.copy() for r in w.regs]
            out = w.step(encode(op, rd, rs1, rs2), mask)
            for lane in range(8):
                expected = alu(op, before[lane][rs1], before[lane][rs2]) if mask >> lane & 1 else 0
                self.assertEqual(out[lane], expected)
                self.assertEqual(w.regs[lane][rd], expected if (mask >> lane & 1 and rd) else before[lane][rd])

    def make_initialized_warp(self):
        w = Warp()
        for lane, regs in enumerate(w.regs):
            regs[1] = lane + 1
            regs[2] = 10
            regs[8] = 0
        return w

    def test_demo_arithmetic_memory_immediate_and_control_flow(self):
        w = self.make_initialized_warp()
        traces = w.run_program(DEMO_PROGRAM, 0xFF)
        self.assertEqual(len(traces), 11)  # branch skips ROM word 9
        self.assertEqual(traces[0], [lane + 11 for lane in range(8)])
        self.assertEqual(traces[1], [(lane + 1) ^ 10 for lane in range(8)])
        self.assertEqual(traces[2], [(lane + 1) * 10 for lane in range(8)])
        self.assertEqual(traces[3], [lane + 1 for lane in range(8)])
        self.assertEqual(traces[4], [0] * 8)
        self.assertEqual(traces[5], [(lane + 1) * 10 for lane in range(8)])
        self.assertEqual(traces[6], [(lane + 1) * 11 for lane in range(8)])
        self.assertEqual(traces[7], [lane + 6 for lane in range(8)])
        self.assertEqual(traces[8], [0] * 8)  # taken branch retirement
        self.assertEqual(traces[9], [2 * lane + 7 for lane in range(8)])
        self.assertEqual(traces[10], [0] * 8)  # not-taken branch retirement
        self.assertEqual([regs[9] for regs in w.regs], [(lane + 1) * 10 for lane in range(8)])
        self.assertEqual([regs[10] for regs in w.regs], [(lane + 1) * 11 for lane in range(8)])
        self.assertEqual([regs[11] for regs in w.regs], [lane + 6 for lane in range(8)])
        self.assertEqual([regs[12] for regs in w.regs], [0] * 8)  # skipped instruction did not execute
        self.assertEqual([regs[13] for regs in w.regs], [2 * lane + 7 for lane in range(8)])

    def test_demo_masked_lanes_and_private_banks(self):
        w = self.make_initialized_warp()
        mask = 0b01010101
        traces = w.run_program(DEMO_PROGRAM, mask)
        self.assertEqual(traces[5], [10, 0, 30, 0, 50, 0, 70, 0])
        self.assertEqual(traces[6], [11, 0, 33, 0, 55, 0, 77, 0])
        self.assertEqual(traces[7], [6, 0, 8, 0, 10, 0, 12, 0])
        self.assertEqual(traces[9], [7, 0, 11, 0, 15, 0, 19, 0])
        self.assertEqual([regs[10] for regs in w.regs], [11, 0, 33, 0, 55, 0, 77, 0])
        self.assertEqual([regs[13] for regs in w.regs], [7, 0, 11, 0, 15, 0, 19, 0])
        self.assertEqual(w.memory[0][0], 10)
        self.assertIsNone(w.memory[1][0])
        self.assertEqual(w.memory[2][0], 30)

    def test_signed_immediate_wraparound(self):
        w = Warp()
        for lane in range(8):
            w.regs[lane][1] = 0x80000000 + lane
        out = w.step(encode_imm(0, 3, 1, -1), 0xFF)
        self.assertEqual(out, [((0x80000000 + lane - 1) & MASK32) for lane in range(8)])
        self.assertEqual([regs[3] for regs in w.regs], out)

    def test_branch_predicates(self):
        w = Warp()
        for regs in w.regs:
            regs[1] = 0xFFFFFFFF
            regs[2] = 1
        self.assertEqual(w.branch_decision(encode_branch(0, 1, 1, 2), 0xFF)[:2], (True, False))
        self.assertEqual(w.branch_decision(encode_branch(1, 1, 1, 2), 0xFF)[:2], (False, False))
        self.assertEqual(w.branch_decision(encode_branch(2, 1, 2, 2), 0xFF)[:2], (True, False))  # signed -1 < 1
        self.assertEqual(w.branch_decision(encode_branch(3, 1, 2, 2), 0xFF)[:2], (False, False))
        self.assertEqual(w.branch_decision(encode_branch(4, 1, 2, 2), 0xFF)[:2], (False, False))  # unsigned max > 1
        self.assertEqual(w.branch_decision(encode_branch(5, 1, 2, 2), 0xFF)[:2], (True, False))
        self.assertEqual(w.branch_decision(encode_branch(6, 0, 0, 2), 0xFF)[:2], (True, False))

    def test_divergent_branch_is_rejected(self):
        w = Warp()
        for lane, regs in enumerate(w.regs):
            regs[1] = lane + 1
            regs[2] = 1 if lane == 0 else 10
        with self.assertRaisesRegex(ValueError, "divergent branch"):
            w.run_program((encode_branch(1, 1, 2, 1),), 0xFF)

    def test_invalid_branch_target_is_rejected(self):
        w = Warp()
        with self.assertRaisesRegex(ValueError, "outside the program"):
            w.run_program((encode_branch(6, 0, 0, 0),), 0xFF)

    def test_load_uninitialized_word_is_rejected_by_reference_model(self):
        w = self.make_initialized_warp()
        load = DEMO_PROGRAM[5]
        with self.assertRaises(ValueError):
            w.step(load, 0xFF)


if __name__ == '__main__':
    unittest.main()
