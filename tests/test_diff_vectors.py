import tempfile
import unittest
from pathlib import Path
from tools.gen_diff_vectors import make_case, write_cases, SEEDS, MASKS


class TestDifferentialVectors(unittest.TestCase):
    def test_all_seeded_cases_are_deterministic_and_masked(self):
        self.assertEqual(len(SEEDS), 4)
        self.assertEqual(len(MASKS), 4)
        for case_id in range(len(SEEDS)):
            a = make_case(case_id)
            b = make_case(case_id)
            self.assertEqual(a, b)
            self.assertEqual(len(a["program"]), 12)
            self.assertEqual(len(a["preload"]), 16)
            self.assertEqual(len(a["expected_regs"]), 8 * 16)
            self.assertEqual(a["retired"], 12)
            for lane in range(8):
                self.assertEqual(a["expected_regs"][lane*16], 0)
                if not ((a["mask"] >> lane) & 1):
                    self.assertEqual(a["expected_mem"][lane], a["sentinels"][lane])

    def test_vector_files_are_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            cases = write_cases(Path(tmp))
            self.assertEqual(len(cases), 4)
            for i in range(4):
                self.assertTrue((Path(tmp) / f"diff_{i}_program.hex").exists())
                self.assertTrue((Path(tmp) / f"diff_{i}_expected_regs.hex").exists())
            self.assertTrue((Path(tmp) / "differential_manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
