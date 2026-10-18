"""OpenGPU v0 ISA functional reference (32-bit modular arithmetic)."""
MASK32 = (1 << 32) - 1
OPS = ('ADD','SUB','AND','OR','XOR','SHL','SHR','MUL')

def encode(op, rd, rs1, rs2):
    assert 0 <= op < 8 and all(0 <= x < 16 for x in (rd, rs1, rs2))
    return (op << 29) | (rd << 25) | (rs1 << 21) | (rs2 << 17)

def alu(op, a, b):
    a &= MASK32
    b &= MASK32
    return ((a+b, a-b, a&b, a|b, a^b, a << (b&31), a >> (b&31), a*b)[op]) & MASK32

class Warp:
    def __init__(self, lanes=8):
        self.regs = [[0]*16 for _ in range(lanes)]

    def step(self, inst, mask):
        op, rd, rs1, rs2 = (inst >> 29)&7, (inst >> 25)&15, (inst >> 21)&15, (inst >> 17)&15
        outputs = []
        for lane, regs in enumerate(self.regs):
            value = alu(op, regs[rs1], regs[rs2]) if (mask >> lane)&1 else 0
            outputs.append(value)
            if (mask >> lane)&1 and rd != 0:
                regs[rd] = value
        return outputs
