#!/usr/bin/env python3
"""Real Swift/C boundary characterization; requires the pinned staged artifacts."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class KoreanBackendNativeTests(unittest.TestCase):
    def test_real_bundle_and_archive_load_offline_with_sandbox_denial(self):
        with tempfile.TemporaryDirectory(prefix="mint-native-packaging-") as directory:
            result = subprocess.run(
                [str(ROOT / "scripts/validate-korean-backend.sh"), "--probe", "--output", directory],
                cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads((Path(directory) / "report.json").read_bytes())
            self.assertTrue(report["packaging"]["unsignedArchive"])
            self.assertTrue(report["packaging"]["sandboxOutsideWriteDenied"])
            self.assertTrue(report["packaging"]["missingModelRefused"])
            self.assertEqual(report["performance"]["cancellation"]["callsAfterCancellation"], 0)
            self.assertEqual(report["performance"]["cancellation"].get("uncancelledControlCalls"), 2)
            self.assertEqual([row["utf16"] for row in report["performance"]["windows"]],
                             [256, 1024, 4096])

    def test_known_utf16_typo_and_spacing_fixtures(self):
        with tempfile.TemporaryDirectory(prefix="mint-native-result-") as directory:
            result = subprocess.run(
                [str(ROOT / "scripts/validate-korean-backend.sh"), "--fixtures", "--output", directory],
                cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads((Path(directory) / "fixtures.json").read_bytes())
            cases = {row["id"]: row for row in report["fixtures"]}
            self.assertEqual(report["version"], "0.24.0")
            self.assertEqual(cases["typo"]["joined"], "그 일은 어제 됐다.")
            self.assertEqual(cases["spacing"]["joined"], "나는 할 수 있다.")
            self.assertIn(("한글", 3, 2),
                          [(t["original"], t["location"], t["length"])
                           for t in cases["mixed"]["tokens"]])
            self.assertTrue(all(row["utf16RangesValid"] for row in cases.values()))


if __name__ == "__main__":
    unittest.main()
