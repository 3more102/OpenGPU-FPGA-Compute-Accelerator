"""OpenGPU v0 ISA functional reference (32-bit modular arithmetic and lane-local memory)."""
MASK32 = (1 << 32) - 1
OPS = ('ADD', 'SUB', 'AND', 'OR', 'XOR', 'SHL', 'SHR', 'MUL')
MEM_DEPTH = 64


def encode(op, rd, rs1, rs2):
    """Encode one canonical register-register instruction."""
    assert 0 <= op < 8 and all(0 <= x < 16 for x in (rd, rs1, rs2))
    return (op << 29) | (rd << 25) | (rs1 << 21) | (rs2 << 17)


def encode_mem(store, reg, base, offset):
    """Encode a lane-local LOAD/STORE with signed word offset."""
    assert 0 <= reg < 16 and 0 <= base < 16
    assert -(1 << 14) <= offset < (1 << 14)
    return (reg << 25) | (base << 21) | (1 << 16) | (int(bool(store)) << 15) | (offset & 0x7FFF)


def alu(op, a, b):
    a &= MASK32
    b &= MASK32
    return ((a + b, a - b, a & b, a | b, a ^ b,
             a << (b & 31), a >> (b & 31), a * b)[op]) & MASK32


DEMO_PROGRAM = (
    encode(0, 3, 1, 2),       # ADD r3, r1, r2
    encode(4, 4, 1, 2),       # XOR r4, r1, r2
    encode(7, 5, 1, 2),       # MUL r5, r1, r2
    encode(1, 6, 3, 2),       # SUB r6, r3, r2
    encode_mem(True, 5, 8, 0), # STORE r5, [r8 + 0]
    encode_mem(False, 9, 8, 0),# LOAD r9, [r8 + 0]
    encode(0, 10, 9, 1),      # ADD r10, r9, r1
)


class Warp:
    def __init__(self, lanes=8):
        self.regs = [[0] * 16 for _ in range(lanes)]
        self.memory = [[None] * MEM_DEPTH for _ in range(lanes)]

    def step(self, inst, mask):
        rd = (inst >> 25) & 15
        rs1 = (inst >> 21) & 15
        if (inst >> 16) & 1:
            store = bool((inst >> 15) & 1)
            offset = inst & 0x7FFF
            if offset & 0x4000:
                offset -= 0x8000
            outputs = []
            for lane, regs in enumerate(self.regs):
                value = 0
                if (mask >> lane) & 1:
                    address = (regs[rs1] + offset) % MEM_DEPTH
                    if store:
                        self.memory[lane][address] = regs[rd]
                    else:
                        value = self.memory[lane][address]
                        if value is None:
                            raise ValueError("LOAD from an uninitialized lane-local memory word")
                        if rd != 0:
                            regs[rd] = value
                outputs.append(value)
            return outputs

        op, rs2 = (inst >> 29) & 7, (inst >> 17) & 15
        outputs = []
        for lane, regs in enumerate(self.regs):
            value = alu(op, regs[rs1], regs[rs2]) if (mask >> lane) & 1 else 0
            outputs.append(value)
            if (mask >> lane) & 1 and rd != 0:
                regs[rd] = value
        return outputs
