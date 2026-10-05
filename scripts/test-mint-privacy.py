#!/usr/bin/env python3
"""Verify actual packaging and rejection of disposable privacy declarations."""
import copy
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parent.parent
if len(sys.argv) < 2:
    sys.exit("Usage: test-mint-privacy.py APP_PATH [TEST_NAME]")
APP = Path(sys.argv.pop(1))
SOURCE = REPO / "Distribution/Resources/PrivacyInfo.xcprivacy"
VALIDATOR = REPO / "scripts/validate-mint-privacy.py"


class PrivacyManifestTests(unittest.TestCase):
    def test_developer_bundle(self):
        manifest = APP / "Contents/Resources/PrivacyInfo.xcprivacy"
        self.assertTrue(manifest.is_file(), "The built macOS app must contain its privacy manifest")
        self.assertEqual(plistlib.loads(manifest.read_bytes()), plistlib.loads(SOURCE.read_bytes()))
        self.validate(APP, True)

    def validate(self, app, accepted):
        result = subprocess.run([sys.executable, str(VALIDATOR), str(app)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)

    def test_packaged_manifest_rejections(self):
        with tempfile.TemporaryDirectory(prefix="mint-privacy-test-") as root:
            root = Path(root)
            app = root / "MINT.app"
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            manifest = resources / "PrivacyInfo.xcprivacy"
            original = plistlib.loads(SOURCE.read_bytes())

            def write(data):
                manifest.write_bytes(plistlib.dumps(data))

            write(original)
            self.validate(app, True)
            with self.subTest("missing root manifest"):
                manifest.rename(resources / "nested.xcprivacy")
                self.validate(app, False)
            with self.subTest("malformed plist"):
                manifest.write_bytes(b"not a plist")
                self.validate(app, False)
            with self.subTest("malformed XML"):
                manifest.write_bytes(b"<?xml version='1.0'?><plist><dict>")
                self.validate(app, False)

            cases = {
                "tracking": {"NSPrivacyTracking": True},
                "integer instead of boolean": {"NSPrivacyTracking": 0},
                "wrong data type": {"NSPrivacyCollectedDataTypes": {}},
                "unrecorded collection": {"NSPrivacyCollectedDataTypes": [{"unexpected": "data"}]},
                "unknown key": {"unexpected": False},
                "missing API category": {"NSPrivacyAccessedAPITypes": []},
                "duplicate category": {"NSPrivacyAccessedAPITypes": original["NSPrivacyAccessedAPITypes"] * 2},
                "noncanonical API inventory": {"NSPrivacyAccessedAPITypes": list(reversed(original["NSPrivacyAccessedAPITypes"]))},
            }
            for name, changes in cases.items():
                with self.subTest(name):
                    data = copy.deepcopy(original)
                    data.update(changes)
                    write(data)
                    self.validate(app, False)
            for name, reasons in [("unknown reason", ["UNKNOWN.1"]),
                                  ("duplicate reason", ["CA92.1", "CA92.1"]),
                                  ("missing reason", [])]:
                with self.subTest(name):
                    data = copy.deepcopy(original)
                    data["NSPrivacyAccessedAPITypes"][0]["NSPrivacyAccessedAPITypeReasons"] = reasons
                    write(data)
                    self.validate(app, False)
            with self.subTest("escaping manifest symlink"):
                manifest.unlink()
                manifest.symlink_to(SOURCE)
                self.validate(app, False)
            with self.subTest("escaping Resources symlink"):
                manifest.unlink()
                resources.rename(root / "external")
                (root / "external/PrivacyInfo.xcprivacy").write_bytes(SOURCE.read_bytes())
                resources.symlink_to(root / "external")
                self.validate(app, False)


if __name__ == "__main__":
    unittest.main()
