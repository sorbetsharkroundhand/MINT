#!/usr/bin/env python3
"""Support reports identify artifacts without reading writer-owned data."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("mint_support", Path(__file__).with_name("collect-mint-support.py"))
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)


class SupportReportTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="mint-support-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.app = self.root / "MINT.app"
        self.contents = self.app / "Contents"
        (self.contents / "MacOS").mkdir(parents=True)
        (self.contents / "Resources").mkdir()
        self.info = {"CFBundleIdentifier": "app.mint.MINT", "CFBundleExecutable": "MINT",
                     "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                     "MINTSourceRevision": "a" * 40, "MINTSourceDirty": False}
        self.write_info()
        (self.contents / "MacOS/MINT").write_bytes(b"fixture executable")
        (self.contents / "Resources/ThirdPartyNotices.json").write_text('{"schemaVersion":1,"models":[]}')

    def write_info(self):
        (self.contents / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_exact_artifact_identity_and_environment(self):
        report = support.collect(self.app)
        app = report["application"]
        self.assertEqual(app["status"], "available")
        self.assertEqual(app["sourceRevision"], "a" * 40)
        self.assertFalse(app["sourceDirty"])
        self.assertEqual(app["executableSHA256"], hashlib.sha256(b"fixture executable").hexdigest())
        self.assertEqual(report["model"]["status"], "not_collected")
        self.assertIn("architecture", report["environment"])
        self.assertIn("osBuild", report["environment"])

    def test_writer_data_preferences_paths_and_logs_are_not_collected(self):
        secret = "PRIVATE-MANUSCRIPT-PROMPT-TITLE"
        for name in ["Documents/draft.md", "Library/MINT/entries.json", "ModelDownloads/config.json",
                     "Library/Preferences/app.mint.MINT.plist", "crash.log"]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(secret)
        (self.contents / "Resources/unrelated.txt").write_text(secret)
        self.info["Unexpected"] = secret
        self.write_info()
        text = json.dumps(support.collect(self.app))
        self.assertNotIn(secret, text)
        self.assertNotIn(str(self.root), text)
        self.assertNotIn("Unexpected", text)

    def test_missing_artifact_and_unidentified_build_are_explicit(self):
        self.assertEqual(support.collect(self.root / "Absent.app")["application"]["status"], "unavailable")
        del self.info["MINTSourceRevision"]
        del self.info["MINTSourceDirty"]
        self.write_info()
        app = support.collect(self.app)["application"]
        self.assertIsNone(app["sourceRevision"])
        self.assertIsNone(app["sourceDirty"])

    def test_owner_supplied_model_context_requires_an_exact_revision(self):
        report = support.collect(self.app, model_id="fixture/approved", model_revision="b" * 40, model_state="unloaded")
        self.assertEqual(report["model"], {"status": "owner_supplied", "id": "fixture/approved",
                                          "revision": "b" * 40, "state": "unloaded"})
        for model_id, revision in [("fixture/approved", None), (None, "b" * 40),
                                   ("fixture/approved", "main"), ("../private", "b" * 40)]:
            with self.subTest(model_id=model_id, revision=revision), self.assertRaises(ValueError):
                support.collect(self.app, model_id=model_id, model_revision=revision)

    def test_app_symlink_traversal_and_noncanonical_metadata_are_rejected(self):
        for field, value in [("CFBundleExecutable", "../../secret"),
                             ("MINTSourceRevision", "main"), ("CFBundleVersion", "private draft title")]:
            with self.subTest(field=field):
                original = dict(self.info)
                self.info[field] = value
                self.write_info()
                with self.assertRaises(ValueError):
                    support.collect(self.app)
                self.info = original
                self.write_info()
        binary = self.contents / "MacOS/MINT"
        binary.unlink()
        binary.symlink_to(self.contents / "Info.plist")
        with self.assertRaises(ValueError):
            support.collect(self.app)

    def test_enclosing_app_directory_cannot_redirect_collection(self):
        selected = self.root / "selected"
        selected.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            support.collect(selected / "MINT.app")

    def test_report_output_never_follows_a_symlink(self):
        report = support.collect(self.app)
        output = self.root / "report.json"
        output.symlink_to(self.contents / "Info.plist")
        original = (self.contents / "Info.plist").read_bytes()
        with self.assertRaises(ValueError):
            support.write_report(output, report)
        self.assertEqual((self.contents / "Info.plist").read_bytes(), original)
        output.unlink()
        output.symlink_to(self.contents, target_is_directory=True)
        with self.assertRaises(ValueError):
            support.write_report(output / "nested/report.json", report)

    def test_export_is_a_private_local_copy_of_allowlisted_fields(self):
        output = self.root / "report.json"
        report = support.collect(self.app)
        support.write_report(output, report)
        self.assertEqual(json.loads(output.read_text()), report)
        self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
