"""OpenGPU v0.2 ISA functional reference (32-bit SIMT arithmetic, memory, immediates and branches)."""
MASK32 = (1 << 32) - 1
OPS = ('ADD', 'SUB', 'AND', 'OR', 'XOR', 'SHL', 'SHR', 'MUL')
MEM_DEPTH = 64


def _signed(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def encode(op, rd, rs1, rs2):
    """Encode a canonical register-register instruction."""
    assert 0 <= op < 8 and all(0 <= x < 16 for x in (rd, rs1, rs2))
    return (op << 29) | (rd << 25) | (rs1 << 21) | (rs2 << 17)


def encode_mem(store, reg, base, offset):
    """Encode lane-local LOAD/STORE with signed 15-bit word offset."""
    assert 0 <= reg < 16 and 0 <= base < 16
    assert -(1 << 14) <= offset < (1 << 14)
    return (reg << 25) | (base << 21) | (1 << 16) | (int(bool(store)) << 15) | (offset & 0x7FFF)


def encode_imm(op, rd, rs1, immediate):
    """Encode an ALU-immediate instruction with signed 16-bit immediate."""
    assert 0 <= op < 8 and 0 <= rd < 16 and 0 <= rs1 < 16
    assert -(1 << 15) <= immediate < (1 << 15)
    return (op << 29) | (rd << 25) | (rs1 << 21) | (15 << 17) | (1 << 16) | (immediate & 0xFFFF)


def encode_branch(op, rs_a, rs_b, offset):
    """Encode a branch with signed PC-relative word offset; op 6 is unconditional JUMP."""
    assert 0 <= op < 8 and 0 <= rs_a < 16 and 0 <= rs_b < 16
    assert -(1 << 15) <= offset < (1 << 15)
    return (op << 29) | (rs_a << 25) | (rs_b << 21) | (14 << 17) | (1 << 16) | (offset & 0xFFFF)


def alu(op, a, b):
    a &= MASK32
    b &= MASK32
    return ((a + b, a - b, a & b, a | b, a ^ b,
             a << (b & 31), a >> (b & 31), a * b)[op]) & MASK32


def _kind(inst):
    if not ((inst >> 16) & 1):
        return "alu"
    op = (inst >> 29) & 7
    tag = (inst >> 17) & 15
    if op == 0 and tag == 0:
        return "memory"
    if tag == 15:
        return "immediate"
    if tag == 14:
        return "branch"
    raise ValueError(f"illegal extended instruction encoding: 0x{inst:08x}")


DEMO_PROGRAM = (
    encode(0, 3, 1, 2),          # 0: ADD r3, r1, r2
    encode(4, 4, 1, 2),          # 1: XOR r4, r1, r2
    encode(7, 5, 1, 2),          # 2: MUL r5, r1, r2
    encode(1, 6, 3, 2),          # 3: SUB r6, r3, r2
    encode_mem(True, 5, 8, 0),   # 4: STORE r5, [r8 + 0]
    encode_mem(False, 9, 8, 0),  # 5: LOAD r9, [r8 + 0]
    encode(0, 10, 9, 1),         # 6: ADD r10, r9, r1
    encode_imm(0, 11, 1, 5),     # 7: ADDI r11, r1, 5
    encode_branch(1, 1, 2, 1),   # 8: BNE r1, r2, +1; skip word 9
    encode_imm(0, 12, 1, 99),    # 9: skipped ADDI
    encode(0, 13, 11, 1),         # 10: ADD r13, r11, r1
    encode_branch(1, 1, 1, 1),   # 11: BNE r1, r1, +1; not taken
)


class Warp:
    def __init__(self, lanes=8):
        self.regs = [[0] * 16 for _ in range(lanes)]
        self.memory = [[None] * MEM_DEPTH for _ in range(lanes)]

    def branch_decision(self, inst, mask):
        """Return (taken, divergent, signed_offset) for a uniform-control-flow branch."""
        if _kind(inst) != "branch":
            raise ValueError("branch_decision requires a branch instruction")
        op = (inst >> 29) & 7
        if op == 7:
            raise ValueError("reserved branch opcode")
        lhs_reg = (inst >> 25) & 15
        rhs_reg = (inst >> 21) & 15
        offset = _signed(inst, 16)
        predicates = []
        for lane, regs in enumerate(self.regs):
            if not ((mask >> lane) & 1):
                continue
            lhs, rhs = regs[lhs_reg] & MASK32, regs[rhs_reg] & MASK32
            if op == 0:
                pred = lhs == rhs
            elif op == 1:
                pred = lhs != rhs
            elif op == 2:
                pred = _signed(lhs, 32) < _signed(rhs, 32)
            elif op == 3:
                pred = _signed(lhs, 32) >= _signed(rhs, 32)
            elif op == 4:
                pred = lhs < rhs
            elif op == 5:
                pred = lhs >= rhs
            else:  # JUMP
                pred = True
            predicates.append(pred)
        if not predicates:
            return False, False, offset
        return predicates[0], any(p != predicates[0] for p in predicates[1:]), offset

    def step(self, inst, mask):
        kind = _kind(inst)
        rd = (inst >> 25) & 15
        rs1 = (inst >> 21) & 15
        if kind == "memory":
            store = bool((inst >> 15) & 1)
            offset = _signed(inst, 15)
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

        if kind == "branch":
            return [0] * len(self.regs)

        op = (inst >> 29) & 7
        if kind == "immediate":
            rhs = _signed(inst, 16)
            outputs = []
            for lane, regs in enumerate(self.regs):
                value = alu(op, regs[rs1], rhs) if (mask >> lane) & 1 else 0
                outputs.append(value)
                if (mask >> lane) & 1 and rd != 0:
                    regs[rd] = value
            return outputs

        rs2 = (inst >> 17) & 15
        outputs = []
        for lane, regs in enumerate(self.regs):
            value = alu(op, regs[rs1], regs[rs2]) if (mask >> lane) & 1 else 0
            outputs.append(value)
            if (mask >> lane) & 1 and rd != 0:
                regs[rd] = value
        return outputs

    def run_program(self, program, mask, max_steps=10000):
        """Execute a program with word-addressed PC; reject divergence and invalid targets."""
        pc = 0
        traces = []
        steps = 0
        while pc < len(program):
            if steps >= max_steps:
                raise ValueError("program exceeded max_steps (possible branch loop)")
            inst = program[pc]
            if _kind(inst) == "branch":
                taken, divergent, offset = self.branch_decision(inst, mask)
                if divergent:
                    raise ValueError(f"divergent branch at PC {pc}")
                traces.append(self.step(inst, mask))
                if taken:
                    target = pc + 1 + offset
                    if not 0 <= target < len(program):
                        raise ValueError(f"branch target {target} is outside the program")
                    pc = target
                else:
                    pc += 1
            else:
                traces.append(self.step(inst, mask))
                pc += 1
            steps += 1
        return traces
