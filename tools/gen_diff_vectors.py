"""Generate reproducible OpenGPU RTL differential-test vectors from the Python ISA model."""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from sim.reference import Warp
from tools.opengpu_asm import assemble

SEEDS = (7, 19, 41, 137)
MASKS = (0xFF, 0x55, 0xA3, 0x00)
SOURCE = ROOT / "examples" / "differential.ogasm"
N_WORDS = 12


def make_case(index: int) -> dict:
    if not 0 <= index < len(SEEDS):
        raise ValueError("unknown case index")
    program = assemble(SOURCE.read_text(encoding="utf-8"), max_words=16)
    if len(program) != N_WORDS:
        raise ValueError(f"expected {N_WORDS} instructions, got {len(program)}")
    rng = random.Random(SEEDS[index])
    mask = MASKS[index]
    warp = Warp(lanes=8)
    preload = []
    sentinels = []
    for lane in range(8):
        r1 = rng.getrandbits(32)
        r2 = rng.randint(1, 7)
        warp.regs[lane][1] = r1
        warp.regs[lane][2] = r2
        preload.extend((r1, r2))
        sentinel = (0xA5000000 | (index << 16) | lane)
        sentinels.append(sentinel)
        warp.memory[lane][0] = sentinel
    traces = warp.run_program(program, mask=mask)
    if len(traces) != N_WORDS:
        raise AssertionError("reference retired the wrong number of instructions")
    expected_regs = [x for lane in warp.regs for x in lane]
    expected_mem = [warp.memory[lane][0] for lane in range(8)]
    if any(x is None for x in expected_mem):
        raise AssertionError("reference memory not initialized")
    return {
        "index": index, "seed": SEEDS[index], "mask": mask,
        "program": program, "preload": preload,
        "sentinels": sentinels, "expected_regs": expected_regs,
        "expected_mem": expected_mem, "retired": len(traces),
    }


def write_cases(outdir: Path) -> list[dict]:
    outdir.mkdir(parents=True, exist_ok=True)
    cases = []
    for i in range(len(SEEDS)):
        case = make_case(i)
        cases.append(case)
        for name in ("program", "preload", "sentinels", "expected_regs", "expected_mem"):
            target = outdir / f"diff_{i}_{name}.hex"
            target.write_text("".join(f"{word & 0xFFFFFFFF:08x}\n" for word in case[name]),
                              encoding="utf-8")
        (outdir / f"diff_{i}_mask.hex").write_text(f"{case['mask']:02x}\n", encoding="utf-8")
    (outdir / "differential_manifest.json").write_text(
        json.dumps([{"case": c["index"], "seed": c["seed"],
                     "mask": c["mask"], "retired": c["retired"]} for c in cases], indent=2)+"\n",
        encoding="utf-8",
    )
    return cases


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", type=Path, default=ROOT / "build")
    args = parser.parse_args()
    cases = write_cases(args.outdir)
    print(f"Generated {len(cases)} seeded OpenGPU differential cases in {args.outdir}")


if __name__ == "__main__":
    main()
