#!/usr/bin/env python3
"""Offline notice-source regressions; no app launch, model or manuscript access."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("mint-notices.py")
spec = importlib.util.spec_from_file_location("mint_notices", SCRIPT)
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)


def digest(data):
    return hashlib.sha256(data).hexdigest()


class NoticeSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mint-notices-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.checkouts = self.root / "checkouts"
        self.package = self.checkouts / "Fixture-Lib"
        self.package.mkdir(parents=True)
        self.license = b"Copyright Fixture Authors\nPermission fixture text.\n"
        (self.package / "LICENSE").write_bytes(self.license)
        (self.package / "source.swift").write_text("// fixture source\n")
        for args in [["init", "-q"], ["add", "."],
                     ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                      "commit", "-qm", "Fixture"]]:
            subprocess.run(["git", "-C", str(self.package), *args], check=True)
        revision = subprocess.check_output(
            ["git", "-C", str(self.package), "rev-parse", "HEAD"], text=True).strip()
        self.lock = {"pins": [{"identity": "fixture-lib", "location": "https://example.invalid/lib",
                               "state": {"revision": revision, "version": "1.0.0"}}]}
        self.inventory = {"schemaVersion": 1, "packages": [{"identity": "fixture-lib",
                          "revision": revision, "notices": [{"path": "LICENSE",
                          "sha256": digest(self.license)}]}], "components": [], "models": []}
        (self.root / "Distribution/Notices").mkdir(parents=True)
        self.write_inputs()

    def write_inputs(self):
        (self.root / "Package.resolved").write_text(json.dumps(self.lock))
        (self.root / "Distribution/Notices/inventory.json").write_text(json.dumps(self.inventory))

    def collect(self):
        self.write_inputs()
        return notices.collect(self.root, self.checkouts)

    def commit_source(self):
        subprocess.run(["git", "-C", str(self.package), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.package), "-c", "user.name=Fixture",
                        "-c", "user.email=fixture@example.invalid", "commit", "-qm", "New fixture source"], check=True)
        revision = subprocess.check_output(["git", "-C", str(self.package), "rev-parse", "HEAD"], text=True).strip()
        self.lock["pins"][0]["state"]["revision"] = revision
        self.inventory["packages"][0]["revision"] = revision

    def test_exact_notice_bytes_and_revisions_are_preserved(self):
        manifest, text = self.collect()
        self.assertIn(self.license.decode(), text)
        self.assertEqual(manifest["packages"][0]["revision"], self.lock["pins"][0]["state"]["revision"])
        self.assertEqual(manifest["models"], [])
        self.assertEqual(self.collect(), (manifest, text))

    def test_missing_license_is_rejected(self):
        self.inventory["packages"][0]["notices"][0]["path"] = "MISSING"
        with self.assertRaises(notices.NoticeError):
            self.collect()

    def test_uninventoried_dependency_or_changed_pin_is_rejected(self):
        for mutation in ["extra", "revision"]:
            with self.subTest(mutation=mutation):
                previous = json.loads(json.dumps(self.lock))
                if mutation == "extra":
                    self.lock["pins"].append({"identity": "unrecorded", "state": {"revision": "a" * 40}})
                else:
                    self.lock["pins"][0]["state"]["revision"] = "a" * 40
                with self.assertRaises(notices.NoticeError):
                    self.collect()
                self.lock = previous

    def test_tampered_notice_and_modified_checkout_are_rejected(self):
        self.inventory["packages"][0]["notices"][0]["sha256"] = "0" * 64
        with self.assertRaises(notices.NoticeError):
            self.collect()
        self.inventory["packages"][0]["notices"][0]["sha256"] = digest(self.license)
        (self.package / "source.swift").write_text("// changed compiled source\n")
        with self.assertRaises(notices.NoticeError):
            self.collect()

    def test_traversal_and_symlink_notices_are_rejected(self):
        outside = self.root / "outside"
        outside.write_bytes(self.license)
        (self.package / "escaped-license").symlink_to(outside)
        self.commit_source()
        for path in ["../outside", "/outside", "nested/../LICENSE", "escaped-license"]:
            with self.subTest(path=path):
                self.inventory["packages"][0]["notices"][0]["path"] = path
                with self.assertRaises(notices.NoticeError):
                    self.collect()

    def test_resource_fingerprints_and_attribution_are_required(self):
        self.inventory["components"] = [{"identity": "fixture-font", "package": "fixture-lib",
            "artifacts": [{"path": "source.swift", "sha256": digest(b"// fixture source\n")}],
            "notices": self.inventory["packages"][0]["notices"],
            "attribution": {"copyright": "Copyright Font Authors", "license": "Original font terms"}}]
        manifest, text = self.collect()
        self.assertIn("Copyright Font Authors", text)
        self.assertIn("Original font terms", text)
        self.assertEqual(manifest["components"][0]["identity"], "fixture-font")
        self.inventory["components"][0]["artifacts"][0]["sha256"] = "0" * 64
        with self.assertRaises(notices.NoticeError):
            self.collect()

    def test_new_distributed_resource_cannot_be_omitted_from_inventory(self):
        assets = self.package / "Assets"
        assets.mkdir()
        (assets / "one.dat").write_bytes(b"one")
        self.commit_source()
        self.inventory["resourceRoots"] = [{"package": "fixture-lib", "path": "Assets"}]
        self.inventory["components"] = [{"identity": "resources", "package": "fixture-lib",
            "artifacts": [{"path": "Assets/one.dat", "sha256": digest(b"one")}],
            "notices": self.inventory["packages"][0]["notices"]}]
        self.collect()
        (assets / "unrecorded.dat").write_bytes(b"new distributed data")
        self.commit_source()
        with self.assertRaises(notices.NoticeError):
            self.collect()

    def test_missing_component_notices_and_unapproved_models_are_rejected(self):
        self.inventory["components"] = [{"identity": "missing-terms", "package": "fixture-lib",
                                          "artifacts": [], "notices": []}]
        with self.assertRaises(notices.NoticeError):
            self.collect()
        self.inventory["components"] = []
        self.inventory["models"] = [{"id": "unapproved/model"}]
        with self.assertRaises(notices.NoticeError):
            self.collect()

    def test_repository_notice_override_retains_explicit_source_provenance(self):
        path = "Distribution/Notices/fixture-LICENSE"
        (self.root / path).write_bytes(self.license)
        self.inventory["packages"][0]["notices"] = [{"root": "repository", "path": path,
                                                    "sha256": digest(self.license)}]
        self.inventory["packages"][0]["licenseProvenance"] = {
            "url": "https://example.invalid/exact-license", "licenseRevision": "b" * 40,
            "coveredGitObjects": {"source.swift": subprocess.check_output(
                ["git", "-C", str(self.package), "rev-parse", "HEAD:source.swift"], text=True).strip()}}
        manifest, text = self.collect()
        self.assertEqual(manifest["packages"][0]["licenseProvenance"],
                         self.inventory["packages"][0]["licenseProvenance"])
        self.assertIn("https://example.invalid/exact-license", text)
        self.inventory["packages"][0]["licenseProvenance"]["coveredGitObjects"]["source.swift"] = "c" * 40
        with self.assertRaises(notices.NoticeError):
            self.collect()

    def packaged_fixture(self, wrapped=False):
        assets = self.package / "Assets"
        assets.mkdir()
        (assets / "font.otf").write_bytes(b"fixture font")
        self.commit_source()
        self.inventory["components"] = [{"identity": "fixture-font", "package": "fixture-lib",
            "artifacts": [{"path": "Assets/font.otf", "sha256": digest(b"fixture font")}],
            "notices": self.inventory["packages"][0]["notices"]}]
        self.inventory["resourceBundles"] = [{"package": "fixture-lib", "name": "Fixture.bundle",
                                              "sourcePrefix": "Assets/", "generated": []}]
        manifest, text = self.collect()
        app = self.root / "Fixture.app"
        resources = app / "Contents/Resources"
        notices.write_output(resources, manifest, text)
        bundle = resources / "Fixture.bundle"
        if wrapped:
            bundle = bundle / "Contents/Resources"
        bundle.mkdir(parents=True)
        shutil.copyfile(assets / "font.otf", bundle / "font.otf")
        return app, resources, bundle, manifest, text

    def test_packaged_notices_and_resources_match_in_both_bundle_layouts(self):
        app, resources, bundle, manifest, text = self.packaged_fixture()
        notices.validate_app(app, manifest, text)
        (bundle / "Contents/Resources").mkdir(parents=True)
        (bundle / "font.otf").rename(bundle / "Contents/Resources/font.otf")
        notices.validate_app(app, manifest, text)

    def test_missing_or_tampered_packaged_notice_is_rejected(self):
        app, resources, _, manifest, text = self.packaged_fixture()
        for name in ["ThirdPartyNotices.json", "ThirdPartyNotices.txt"]:
            path = resources / name
            original = path.read_bytes()
            path.unlink()
            with self.assertRaises(notices.NoticeError):
                notices.validate_app(app, manifest, text)
            path.write_bytes(original + b"tampered")
            with self.assertRaises(notices.NoticeError):
                notices.validate_app(app, manifest, text)
            path.write_bytes(original)

    def test_missing_changed_unrecorded_and_symlink_resources_are_rejected(self):
        app, resources, bundle, manifest, text = self.packaged_fixture()
        font = bundle / "font.otf"
        font.unlink()
        with self.assertRaises(notices.NoticeError):
            notices.validate_app(app, manifest, text)
        font.write_bytes(b"changed")
        with self.assertRaises(notices.NoticeError):
            notices.validate_app(app, manifest, text)
        font.unlink()
        font.symlink_to(self.package / "Assets/font.otf")
        with self.assertRaises(notices.NoticeError):
            notices.validate_app(app, manifest, text)
        font.unlink()
        font.write_bytes(b"fixture font")
        for path in [resources / "model.safetensors", resources / "unapproved.gguf",
                     resources / "unrecorded.dat", app / "Contents/MacOS/weights.bin"]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"unrecorded")
            with self.assertRaises(notices.NoticeError):
                notices.validate_app(app, manifest, text)
            path.unlink()


if __name__ == "__main__":
    unittest.main()
