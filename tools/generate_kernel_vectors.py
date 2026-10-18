"""Deterministic OpenGPU compute kernels for end-to-end RTL differential testing.

This script assembles source programs, executes the architectural Python model,
checks independent mathematical expectations, and writes simulation fixture hex.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from sim.reference import MASK32, Warp
from tools.opengpu_asm import assemble

LANES = 8
PROGRAM_CAPACITY = 16
INPUTS = (0, 1, 0xFFFFFFFF, 0x80000000, 7, 1024, 0xABCDEF01, 65535)
CASES = {
    "add7_all": ("examples/vector_add7.ogasm", 0xFF, "add7"),
    "add7_mask55": ("examples/vector_add7.ogasm", 0x55, "add7"),
    "invert_all": ("examples/vector_invert.ogasm", 0xFF, "invert"),
    "square_plus3_maskaa": ("examples/vector_square3.ogasm", 0xAA, "square3"),
    "subtract17_all": ("examples/vector_sub17.ogasm", 0xFF, "sub17"),
}


def expected_operation(op: str, value: int) -> int:
    if op == "add7":
        return (value + 7) & MASK32
    if op == "invert":
        return (value ^ MASK32) & MASK32
    if op == "square3":
        return (value * value + 3) & MASK32
    if op == "sub17":
        return (value - 17) & MASK32
    raise ValueError(f"unknown operation {op!r}")


def build_case(name: str, root: Path) -> dict:
    if name not in CASES:
        raise ValueError(f"unknown fixture {name!r}")
    source_file, mask, operation = CASES[name]
    words = assemble((root / source_file).read_text(encoding="utf-8"),
                     max_words=PROGRAM_CAPACITY)
    if not 0 < len(words) <= PROGRAM_CAPACITY:
        raise ValueError("invalid program length")

    warp = Warp(lanes=LANES)
    sentinels = [(0xA5001000 + lane * 0x101) & MASK32 for lane in range(LANES)]
    for lane in range(LANES):
        warp.memory[lane][0] = INPUTS[lane]
        warp.memory[lane][1] = sentinels[lane]

    traces = warp.run_program(words, mask)
    if len(traces) != len(words):
        raise AssertionError("kernel fixtures must be straight-line programs")
    expected_mem = []
    expected_regs = []
    for lane in range(LANES):
        active = bool((mask >> lane) & 1)
        expected = expected_operation(operation, INPUTS[lane])
        expected_mem.append(expected if active else sentinels[lane])
        expected_regs.append(expected if active else 0)
        if warp.memory[lane][0] != INPUTS[lane]:
            raise AssertionError(f"input changed in {name} lane {lane}")
        if warp.memory[lane][1] != expected_mem[-1]:
            raise AssertionError(f"reference memory mismatch in {name} lane {lane}")
        if warp.regs[lane][5] != expected_regs[-1]:
            raise AssertionError(f"reference register mismatch in {name} lane {lane}")
    return {
        "name": name, "source": source_file, "operation": operation,
        "mask": mask, "length": len(words),
        "program": words + [0] * (PROGRAM_CAPACITY - len(words)),
        "inputs": list(INPUTS), "sentinels": sentinels,
        "expected_memory": expected_mem, "expected_r5": expected_regs,
    }


def write_fixtures(output: Path, root: Path) -> list[dict]:
    output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name in CASES:
        record = build_case(name, root)
        for field, filename in (
            ("program", "program.hex"),
            ("inputs", "inputs.hex"),
            ("sentinels", "sentinels.hex"),
            ("expected_memory", "expected_memory.hex"),
            ("expected_r5", "expected_r5.hex"),
        ):
            (output / f"{name}_{filename}").write_text(
                "".join(f"{word & MASK32:08x}\n" for word in record[field]),
                encoding="utf-8",
            )
        manifest.append({
            "name": name, "mask": record["mask"], "length": record["length"],
            "source": record["source"],
        })
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/kernel_vectors"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = write_fixtures(args.output, root)
    print(f"Generated {len(manifest)} deterministic kernel fixtures in {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
