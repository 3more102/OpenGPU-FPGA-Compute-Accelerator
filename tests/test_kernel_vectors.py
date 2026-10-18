"""Fixture tests independent of hardware and CI tools."""
import tempfile
import unittest
from pathlib import Path

from tools.generate_kernel_vectors import (
    CASES, INPUTS, MASK32, build_case, expected_operation, write_fixtures
)

ROOT = Path(__file__).resolve().parents[1]


class TestKernelVectors(unittest.TestCase):
    def test_reference_matches_math_for_all_cases(self):
        for case_name in CASES:
            with self.subTest(case=case_name):
                item = build_case(case_name, ROOT)
                self.assertEqual(len(item["program"]), 16)
                self.assertEqual(item["inputs"], list(INPUTS))
                self.assertTrue(0 < item["length"] <= 16)
                self.assertTrue(0 < item["mask"] < 256)
                for lane in range(8):
                    active = bool(item["mask"] & (1 << lane))
                    mathematical_result = expected_operation(item["operation"], INPUTS[lane])
                    self.assertEqual(item["expected_r5"][lane],
                                     mathematical_result if active else 0)
                    self.assertEqual(item["expected_memory"][lane],
                                     mathematical_result if active else item["sentinels"][lane])

    def test_overflow_and_sign_cases(self):
        self.assertEqual(expected_operation("add7", MASK32), 6)
        self.assertEqual(expected_operation("sub17", 0), MASK32 - 16)
        self.assertEqual(expected_operation("invert", 0), MASK32)
        self.assertEqual(expected_operation("square3", MASK32), 4)

    def test_hex_fixtures_and_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            manifest = write_fixtures(out, ROOT)
            self.assertEqual(len(manifest), len(CASES))
            for entry in manifest:
                prefix = entry["name"]
                path = out / f"{prefix}_program.hex"
                lines = path.read_text(encoding="utf-8").splitlines()
                self.assertEqual(len(lines), 16)
                self.assertEqual(len(out.joinpath(f"{prefix}_expected_memory.hex")
                                     .read_text(encoding="utf-8").splitlines()), 8)
                self.assertTrue(all(len(line) == 8 for line in lines))


if __name__ == "__main__":
    unittest.main()
