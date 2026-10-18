"""Two-pass assembler/disassembler for the OpenGPU v0.2 demonstration ISA."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

MASK32 = 0xFFFFFFFF
ALU_OPS = {
    "ADD": 0, "SUB": 1, "AND": 2, "OR": 3,
    "XOR": 4, "SHL": 5, "SHR": 6, "MUL": 7,
}
BRANCH_OPS = {
    "BEQ": 0, "BNE": 1, "BLT": 2, "BGE": 3,
    "BLTU": 4, "BGEU": 5, "JUMP": 6, "JMP": 6,
}
BRANCH_NAMES = {0: "BEQ", 1: "BNE", 2: "BLT", 3: "BGE",
                4: "BLTU", 5: "BGEU", 6: "JUMP"}


def signed(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def parse_int(token: str, line_no: int) -> int:
    try:
        return int(token.strip(), 0)
    except ValueError:
        try:
            return int(token.strip(), 10)
        except ValueError as exc:
            raise ValueError(f"line {line_no}: invalid integer {token!r}") from exc


def parse_reg(token: str, line_no: int) -> int:
    match = re.fullmatch(r"[rR](\d+)", token.strip())
    if not match:
        raise ValueError(f"line {line_no}: expected register r0..r15, got {token!r}")
    reg = int(match.group(1))
    if not 0 <= reg <= 15:
        raise ValueError(f"line {line_no}: register index out of range: {token!r}")
    return reg


def _check_signed(value: int, bits: int, what: str, line_no: int) -> int:
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise ValueError(f"line {line_no}: {what} {value} does not fit signed {bits} bits")
    return value


def encode_alu(op: int, rd: int, rs1: int, rs2: int) -> int:
    return ((op & 7) << 29) | ((rd & 15) << 25) | ((rs1 & 15) << 21) | ((rs2 & 15) << 17)


def encode_imm(op: int, rd: int, rs1: int, immediate: int) -> int:
    return (((op & 7) << 29) | ((rd & 15) << 25) | ((rs1 & 15) << 21)
            | (15 << 17) | (1 << 16) | (immediate & 0xFFFF))


def encode_mem(store: bool, reg: int, base: int, offset: int) -> int:
    return ((reg & 15) << 25) | ((base & 15) << 21) | (1 << 16) | (int(store) << 15) | (offset & 0x7FFF)


def encode_branch(op: int, rs_a: int, rs_b: int, offset: int) -> int:
    return (((op & 7) << 29) | ((rs_a & 15) << 25) | ((rs_b & 15) << 21)
            | (14 << 17) | (1 << 16) | (offset & 0xFFFF))


def _strip_comment(line: str) -> str:
    return re.split(r"#|//|;", line, maxsplit=1)[0].strip()


def _parse_memory(token: str, line_no: int) -> tuple[int, int]:
    match = re.fullmatch(r"\[\s*([rR]\d+)\s*(?:(\+|-)\s*(.*?)\s*)?\]", token.strip())
    if not match:
        raise ValueError(f"line {line_no}: expected memory operand like [r8 + 0], got {token!r}")
    base = parse_reg(match.group(1), line_no)
    sign = match.group(2)
    offset_text = match.group(3)
    if not sign:
        offset = 0
    else:
        if not offset_text:
            raise ValueError(f"line {line_no}: missing memory offset")
        offset = parse_int(offset_text, line_no)
        if sign == "-":
            offset = -offset
    return base, _check_signed(offset, 15, "memory offset", line_no)


def _branch_offset(token: str, labels: dict[str, int], pc: int, line_no: int) -> int:
    key = token.strip().lower()
    if key in labels:
        offset = labels[key] - (pc + 1)
    elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token.strip()):
        raise ValueError(f"line {line_no}: undefined label {token.strip()!r}")
    else:
        offset = parse_int(token, line_no)
    return _check_signed(offset, 16, "branch offset", line_no)


def _encode_line(text: str, labels: dict[str, int], pc: int, line_no: int) -> int:
    parts = re.match(r"^([A-Za-z][A-Za-z0-9_]*)\s*(.*?)\s*$", text)
    if not parts:
        raise ValueError(f"line {line_no}: expected an instruction")
    mnemonic = parts.group(1).upper()
    operand_text = parts.group(2).strip()
    operands = [] if not operand_text else [part.strip() for part in operand_text.split(",")]

    if mnemonic == "NOP":
        if operands:
            raise ValueError(f"line {line_no}: NOP takes no operands")
        return encode_alu(0, 0, 0, 0)

    if mnemonic in ALU_OPS:
        if len(operands) != 3:
            raise ValueError(f"line {line_no}: {mnemonic} requires rd, rs1, rs2")
        rd, rs1, rs2 = (parse_reg(item, line_no) for item in operands)
        return encode_alu(ALU_OPS[mnemonic], rd, rs1, rs2)

    if mnemonic.endswith("I") and mnemonic[:-1] in ALU_OPS:
        if len(operands) != 3:
            raise ValueError(f"line {line_no}: {mnemonic} requires rd, rs1, immediate")
        rd = parse_reg(operands[0], line_no)
        rs1 = parse_reg(operands[1], line_no)
        immediate = _check_signed(parse_int(operands[2], line_no), 16, "immediate", line_no)
        return encode_imm(ALU_OPS[mnemonic[:-1]], rd, rs1, immediate)

    if mnemonic in ("LOAD", "STORE"):
        if len(operands) != 2:
            raise ValueError(f"line {line_no}: {mnemonic} requires register, [base + offset]")
        reg = parse_reg(operands[0], line_no)
        base, offset = _parse_memory(operands[1], line_no)
        return encode_mem(mnemonic == "STORE", reg, base, offset)

    if mnemonic in BRANCH_OPS:
        op = BRANCH_OPS[mnemonic]
        expected_count = 1 if op == 6 else 3
        if len(operands) != expected_count:
            signature = "target" if op == 6 else "rs_a, rs_b, target"
            raise ValueError(f"line {line_no}: {mnemonic} requires {signature}")
        if op == 6:
            offset = _branch_offset(operands[0], labels, pc, line_no)
            return encode_branch(op, 0, 0, offset)
        rs_a = parse_reg(operands[0], line_no)
        rs_b = parse_reg(operands[1], line_no)
        offset = _branch_offset(operands[2], labels, pc, line_no)
        return encode_branch(op, rs_a, rs_b, offset)

    raise ValueError(f"line {line_no}: unknown mnemonic {mnemonic!r}")


def assemble(source: str, max_words: int = 16) -> list[int]:
    """Assemble source text into 32-bit instruction words."""
    if max_words < 1:
        raise ValueError("max_words must be positive")
    labels: dict[str, int] = {}
    statements: list[tuple[int, str]] = []

    for line_no, original in enumerate(source.splitlines(), start=1):
        line = _strip_comment(original)
        while line:
            label_match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):", line)
            if not label_match:
                break
            name = label_match.group(1).lower()
            if name in labels:
                raise ValueError(f"line {line_no}: duplicate label {label_match.group(1)!r}")
            labels[name] = len(statements)
            line = line[label_match.end():].strip()
        if line:
            statements.append((line_no, line))

    if len(statements) > max_words:
        raise ValueError(f"program has {len(statements)} words; maximum is {max_words}")

    words = []
    for pc, (line_no, statement) in enumerate(statements):
        words.append(_encode_line(statement, labels, pc, line_no) & MASK32)
    return words


def disassemble_word(word: int) -> str:
    """Decode one word into canonical assembly syntax."""
    if not 0 <= word <= MASK32:
        raise ValueError(f"instruction word out of range: {word}")
    op = (word >> 29) & 7
    rd = (word >> 25) & 15
    rs1 = (word >> 21) & 15
    rs2 = (word >> 17) & 15

    if not ((word >> 16) & 1):
        return f"{tuple(ALU_OPS.keys())[op]} r{rd}, r{rs1}, r{rs2}"

    if op == 0 and rs2 == 0:
        store = bool((word >> 15) & 1)
        reg = rd
        base = rs1
        offset = signed(word, 15)
        if offset < 0:
            address = f"[r{base} - {abs(offset)}]"
        else:
            address = f"[r{base} + {offset}]"
        return f"{'STORE' if store else 'LOAD'} r{reg}, {address}"

    if rs2 == 15:
        immediate = signed(word, 16)
        return f"{tuple(ALU_OPS.keys())[op]}I r{rd}, r{rs1}, {immediate}"

    if rs2 == 14:
        if op == 7:
            raise ValueError(f"illegal reserved branch opcode in 0x{word:08x}")
        offset = signed(word, 16)
        name = BRANCH_NAMES[op]
        if op == 6:
            return f"JUMP {offset:+d}"
        return f"{name} r{rd}, r{rs1}, {offset:+d}"

    raise ValueError(f"illegal extended instruction encoding: 0x{word:08x}")


def disassemble(words: list[int]) -> list[str]:
    return [disassemble_word(word) for word in words]


def _read_hex_words(path: Path) -> list[int]:
    words = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        token = _strip_comment(line)
        if not token:
            continue
        try:
            words.append(int(token, 16))
        except ValueError as exc:
            raise ValueError(f"line {line_no}: invalid hexadecimal word {token!r}") from exc
    return words


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="assembly source, or hex words with --disassemble")
    parser.add_argument("-o", "--output", type=Path, help="output path; stdout if omitted")
    parser.add_argument("--format", choices=("hex", "json"), default="hex",
                        help="assembled output format (default: hex)")
    parser.add_argument("--max-words", type=int, default=16,
                        help="maximum number of instruction words (default: 16)")
    parser.add_argument("--disassemble", action="store_true",
                        help="read hexadecimal words and print canonical assembly")
    args = parser.parse_args(argv)

    try:
        if args.disassemble:
            result = "\n".join(disassemble(_read_hex_words(args.input))) + "\n"
        else:
            words = assemble(args.input.read_text(encoding="utf-8"), args.max_words)
            if args.format == "json":
                result = json.dumps(words, indent=2) + "\n"
            else:
                result = "".join(f"{word:08x}\n" for word in words)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(result, encoding="utf-8")
        else:
            print(result, end="")
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
