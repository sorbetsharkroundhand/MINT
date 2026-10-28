#!/usr/bin/env python3
"""Exercise artifact validation against real synthetic archives, without network access."""
import hashlib
import io
import json
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().with_name("validate-korean-backend.sh")
sys.path.insert(0, str(SCRIPT.parent / "korean-backend-probe"))
from artifacts import ValidationError
from budgets import compare


class KoreanBackendValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="purlory-korean-validation-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "archives").mkdir()
        self.manifest = {
            "schemaVersion": 1,
            "source": {"revision": "6e16bbcfc0940fabccbdde574abb4ea3a659588e"},
            "assets": [],
        }
        self.add_archive("native", "zip", [("Kiwi.framework/Kiwi", b"synthetic-library")])
        self.add_archive("model", "tar.gz", [("model/knlm.model", b"synthetic-model")])

    def add_archive(self, identity, kind, entries, symlink=False):
        path = self.root / "archives" / (identity + (".zip" if kind == "zip" else ".tgz"))
        if kind == "zip":
            with zipfile.ZipFile(path, "w") as archive:
                for name, data in entries:
                    info = zipfile.ZipInfo(name)
                    if symlink:
                        info.create_system = 3
                        info.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(info, data)
        else:
            with tarfile.open(path, "w:gz") as archive:
                for name, data in entries:
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
        record = {
            "id": identity,
            "name": path.name,
            "kind": kind,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "files": [{"path": name, "sha256": hashlib.sha256(data).hexdigest(),
                       "bytes": len(data)} for name, data in entries],
        }
        self.manifest["assets"] = [a for a in self.manifest["assets"] if a["id"] != identity] + [record]

    def validate(self):
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        if not SCRIPT.is_file():
            return subprocess.CompletedProcess([], 127, "", "validator is not implemented")
        return subprocess.run(
            [str(SCRIPT), "--check-inputs", "--manifest", str(manifest),
             "--artifacts-root", str(self.root)], capture_output=True, text=True)

    def assert_rejected(self, reason):
        result = self.validate()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn(reason, result.stderr)
        self.assertFalse((self.root.parent / "escaped-model").exists())

    def test_valid_archives_are_verified_and_extracted_exactly(self):
        # Reject-all implementations and validators that never inspect bytes fail here.
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "extracted/native/Kiwi.framework/Kiwi").read_bytes(),
                         b"synthetic-library")
        self.assertEqual((self.root / "extracted/model/model/knlm.model").read_bytes(),
                         b"synthetic-model")

    @unittest.skipUnless(sys.platform == "darwin", "Apple system Python compatibility")
    def test_system_python_verifies_artifacts_without_newer_hashlib_apis(self):
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        result = subprocess.run(["/usr/bin/python3", str(SCRIPT.parent / "korean-backend-probe/validate.py"),
                                 "--check-inputs", "--manifest", str(manifest),
                                 "--artifacts-root", str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "extracted/model/model/knlm.model").read_bytes(), b"synthetic-model")

    def test_wrong_archive_sha256_is_rejected_before_extraction(self):
        self.manifest["assets"][0]["sha256"] = "0" * 64
        self.assert_rejected("archive hash")
        self.assertFalse((self.root / "extracted/native").exists())

    def test_archive_parent_traversal_is_rejected(self):
        self.add_archive("model", "tar.gz", [("../escaped-model", b"escape")])
        self.assert_rejected("unsafe path")

    def test_zip_symlink_is_rejected(self):
        self.add_archive("native", "zip", [("library", b"../../outside")], symlink=True)
        self.assert_rejected("symlink")

    def test_missing_model_archive_is_rejected(self):
        (self.root / "archives/model.tgz").unlink()
        self.assert_rejected("missing archive")

    def test_unrecorded_native_file_is_rejected(self):
        self.add_archive("native", "zip", [("library", b"ok"), ("hidden.dylib", b"unknown")])
        self.manifest["assets"][-1]["files"].pop()
        self.assert_rejected("unrecorded")

    def test_changed_extracted_file_is_rejected(self):
        self.assertEqual(self.validate().returncode, 0)
        (self.root / "extracted/model/model/knlm.model").write_bytes(b"changed")
        self.assert_rejected("extracted hash")

    def test_symlinked_staging_path_cannot_escape(self):
        external = self.root / "outside"
        external.mkdir()
        (self.root / "extracted").symlink_to(external, target_is_directory=True)
        self.assert_rejected("symlink")
        self.assertEqual(list(external.iterdir()), [])

    def check_metrics(self, metrics, latency_limit=125):
        (self.root / "report.json").write_text(json.dumps({"metrics": metrics}))
        (self.root / "budgets.json").write_text(json.dumps({
            "schemaVersion": 1, "metrics": {
                "native1024NS": {"baselineMaximum": 100, "limit": latency_limit, "unit": "ns"},
                "peakResidentBytes": {"baselineMaximum": 1000, "limit": 1100, "unit": "bytes"},
            }}))
        return subprocess.run([str(SCRIPT), "--check-metrics", str(self.root / "report.json"),
                               "--budgets", str(self.root / "budgets.json")],
                              capture_output=True, text=True)

    def test_measured_metrics_within_frozen_budgets_pass(self):
        result = self.check_metrics({"native1024NS": 125, "peakResidentBytes": 1100})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nonfinite_frozen_limit_cannot_bypass_regression_gate(self):
        result = self.check_metrics({"native1024NS": 9999, "peakResidentBytes": 1000},
                                    latency_limit=float("nan"))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("invalid frozen metric", result.stderr)

    def test_changed_artifact_or_native_cap_cannot_reuse_frozen_gate(self):
        baseline = {"schemaVersion": 1, "manifestSHA256": "approved", "nativeCallMaxUTF16": 1024,
                    "metrics": {"native1024NS": {"baselineMaximum": 100, "limit": 125, "unit": "ns"}}}
        for changes in ({"manifestSHA256": "changed"}, {"nativeCallMaxUTF16": 4096}):
            with self.subTest(changes=changes), self.assertRaises(ValidationError):
                compare({"metrics": {"native1024NS": 100}, "manifestSHA256": "approved",
                         "nativeCallMaxUTF16": 1024, **changes}, baseline)

    def test_nonempty_probe_output_is_preserved(self):
        output = self.root / "owned-output"
        output.mkdir()
        (output / "retained.txt").write_text("preserve")
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(self.manifest))
        result = subprocess.run([str(SCRIPT), "--probe", "--manifest", str(manifest),
                                 "--artifacts-root", str(self.root), "--output", str(output)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("output directory must be empty", result.stderr)
        self.assertEqual([p.name for p in output.iterdir()], ["retained.txt"])

    def test_measured_regression_and_incomplete_metrics_fail(self):
        for metrics, reason in [({"native1024NS": 126, "peakResidentBytes": 1000}, "budget regression"),
                                ({"native1024NS": 1}, "missing metrics"),
                                ({"native1024NS": -1, "peakResidentBytes": 10}, "invalid metric")]:
            with self.subTest(metrics=metrics):
                result = self.check_metrics(metrics)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn(reason, result.stderr)


if __name__ == "__main__":
    unittest.main()
