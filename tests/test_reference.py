import random
import unittest
from sim.reference import DEMO_PROGRAM, Warp, alu, encode, MASK32


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

    def test_demo_program_all_lanes(self):
        w = Warp()
        for lane, regs in enumerate(w.regs):
            regs[1] = lane + 1
            regs[2] = 10
        traces = [w.step(inst, 0xFF) for inst in DEMO_PROGRAM]
        self.assertEqual(traces[0], [lane + 11 for lane in range(8)])
        self.assertEqual(traces[1], [(lane + 1) ^ 10 for lane in range(8)])
        self.assertEqual(traces[2], [(lane + 1) * 10 for lane in range(8)])
        self.assertEqual(traces[3], [lane + 1 for lane in range(8)])
        self.assertEqual([regs[6] for regs in w.regs], [lane + 1 for lane in range(8)])

    def test_demo_program_masked_lanes(self):
        w = Warp()
        for lane, regs in enumerate(w.regs):
            regs[1] = lane + 1
            regs[2] = 10
        mask = 0b01010101
        for inst in DEMO_PROGRAM:
            out = w.step(inst, mask)
        self.assertEqual(out, [1, 0, 3, 0, 5, 0, 7, 0])
        self.assertEqual([regs[6] for regs in w.regs], [1, 0, 3, 0, 5, 0, 7, 0])


if __name__ == '__main__':
    unittest.main()
