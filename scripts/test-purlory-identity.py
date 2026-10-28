#!/usr/bin/env python3
"""Identity and icon regressions, isolated from manuscripts and model downloads."""
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

class IdentityTests(unittest.TestCase):
    def test_package_and_scheme_use_new_identity(self):
        package = (ROOT / 'Package.swift').read_text()
        self.assertIn('name: "PurloryCore"', package)
        self.assertIn('name: "PurloryBench"', package)
        self.assertTrue((ROOT / 'Distribution/Purlory.xcodeproj/xcshareddata/xcschemes/Purlory.xcscheme').is_file())

    def test_icon_accepts_real_resource_and_rejects_missing_corrupt_and_wrong_reference(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = pathlib.Path(tmp) / 'Purlory.app'
            resources = app / 'Contents/Resources'
            resources.mkdir(parents=True)
            info = app / 'Contents/Info.plist'
            info.write_bytes(plistlib.dumps({'CFBundleIconFile': 'AppIcon'}))
            icon = resources / 'AppIcon.icns'
            def validate():
                return subprocess.run(['python3', str(ROOT / 'scripts/validate-purlory-icon.py'), str(app)], capture_output=True)
            shutil.copyfile(ROOT / 'Distribution/Resources/AppIcon.icns', icon)
            self.assertEqual(validate().returncode, 0)
            icon.unlink()
            self.assertNotEqual(validate().returncode, 0)
            icon.write_bytes(b'icns\x00\x00\x00\x08')
            self.assertNotEqual(validate().returncode, 0)
            shutil.copyfile(ROOT / 'Distribution/Resources/AppIcon.icns', icon)
            info.write_bytes(plistlib.dumps({'CFBundleIconFile': '../AppIcon'}))
            self.assertNotEqual(validate().returncode, 0)

if __name__ == '__main__':
    unittest.main()
