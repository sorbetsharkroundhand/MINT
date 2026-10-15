#!/usr/bin/env python3
"""Verify static-library packaging preserves verified bytes and refuses link escapes."""
import hashlib
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / "korean-backend-probe"))
import prepare
from artifacts import ValidationError


class KoreanBackendPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mint-kiwi-preparation-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.output = self.root / "artifacts"
        self.files = []
        for path, data in [("Kiwi", b"verified-static-archive"),
                           ("Headers/capi.h", b"synthetic-header"),
                           ("Headers/Macro.h", b"synthetic-macro")]:
            relative = "Kiwi.xcframework/macos-arm64_x86_64/Kiwi.framework/" + path
            file = self.source / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            self.files.append({"path": relative, "sha256": hashlib.sha256(data).hexdigest()})

    def test_static_layout_preserves_binary_and_headers(self):
        prepare.prepare_static_library(self.source, self.output, self.files)
        bundle = self.output / "KiwiStatic.xcframework"
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        library = info["AvailableLibraries"][0]
        self.assertEqual(library["LibraryPath"], "libKiwi.a")
        self.assertEqual(library["SupportedArchitectures"], ["arm64", "x86_64"])
        variant = bundle / library["LibraryIdentifier"]
        self.assertEqual((variant / library["LibraryPath"]).read_bytes(), b"verified-static-archive")
        self.assertEqual((variant / library["HeadersPath"] / "Kiwi/capi.h").read_bytes(), b"synthetic-header")
        self.assertEqual(list(bundle.rglob("*.framework")), [])
        prepare.prepare_static_library(self.source, self.output, self.files)

    def test_changed_input_is_rejected(self):
        (self.source / self.files[0]["path"]).write_bytes(b"unverified-library")
        with self.assertRaises(ValidationError):
            prepare.prepare_static_library(self.source, self.output, self.files)

    def test_destination_symlink_is_rejected_without_external_write(self):
        outside = self.root / "outside"
        outside.mkdir()
        self.output.mkdir()
        (self.output / "KiwiStatic.xcframework").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValidationError):
            prepare.prepare_static_library(self.source, self.output, self.files)
        self.assertEqual(list(outside.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
