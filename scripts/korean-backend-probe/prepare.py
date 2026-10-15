#!/usr/bin/env python3
"""Reconstruct only the pinned native package inputs, without touching user data."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import tempfile

from artifacts import ValidationError, checked_path, file_digest, load_manifest, verify_inputs
from probe import fetch_missing


def copy_verified(source, destination, expected):
    if destination.is_symlink():
        raise ValidationError("symlink in reconstructed package")
    if destination.is_file() and file_digest(destination) == expected:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".prepare-", dir=destination.parent, delete=False) as staged:
        temporary = Path(staged.name)
    try:
        shutil.copyfile(source, temporary)
        temporary.chmod(0o644)
        if file_digest(temporary) != expected:
            raise ValidationError("changed reconstructed package bytes")
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def prepare_static_library(source_root, artifacts, files):
    # The published framework contains a static archive and no framework Info.plist.
    # Describe those same bytes as a static library so Xcode links without embedding it.
    bundle = checked_path(artifacts, "KiwiStatic.xcframework")
    variant = "macos-arm64_x86_64"
    prefix = "Kiwi.xcframework/" + variant + "/Kiwi.framework/"
    outputs = {"Kiwi": "libKiwi.a", "Headers/capi.h": "include/Kiwi/capi.h",
               "Headers/Macro.h": "include/Kiwi/Macro.h"}
    records = {row["path"]: row for row in files}
    for original, relative in outputs.items():
        row = records[prefix + original]
        source = checked_path(source_root, row["path"])
        if file_digest(source) != row["sha256"]:
            raise ValidationError("changed static-library input")
        copy_verified(source, checked_path(bundle, variant + "/" + relative), row["sha256"])
    module = checked_path(bundle, variant + "/include/module.modulemap")
    module.write_text('module Kiwi { header "Kiwi/capi.h" export * }\n')
    info = {"CFBundlePackageType": "XFWK", "XCFrameworkFormatVersion": "1.0",
            "AvailableLibraries": [{"LibraryIdentifier": variant, "LibraryPath": "libKiwi.a",
                                    "HeadersPath": "include", "SupportedArchitectures": ["arm64", "x86_64"],
                                    "SupportedPlatform": "macos"}]}
    checked_path(bundle, "Info.plist").write_bytes(plistlib.dumps(info, sort_keys=True))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts-root", type=Path, default=Path("build/korean-backend-validation"))
    args = parser.parse_args()
    manifest_path = Path("Distribution/KoreanBackend/artifacts.json")
    budgets = load_manifest(Path("Distribution/KoreanBackend/budgets.json"))
    if file_digest(manifest_path) != budgets["manifestSHA256"]:
        raise ValidationError("backend manifest differs from the validated promotion gate")
    manifest = load_manifest(manifest_path)
    fetch_missing(manifest, args.artifacts_root)
    verify_inputs(manifest, args.artifacts_root)
    package = Path("Packages/MINTKoreanBackend")
    resources = package / "Sources/MINTKoreanBackend/Resources/Kiwi"
    artifacts = package / "Artifacts"
    for destination in (resources, artifacts):
        checked_path(Path.cwd(), str(destination)).mkdir(parents=True, exist_ok=True)
    for asset in manifest["assets"]:
        source_root = args.artifacts_root / "extracted" / asset["id"]
        if asset["id"] == "native":
            prepare_static_library(source_root, artifacts, asset["files"])
            continue
        for row in asset["files"]:
            copy_verified(checked_path(source_root, row["path"]),
                          checked_path(resources, row["path"]), row["sha256"])
    notices = resources / "Notices"
    checked_path(resources, "Notices").mkdir(exist_ok=True)
    for row in manifest["notices"]:
        source = checked_path(Path.cwd(), row["path"])
        if file_digest(source) != row["sha256"]:
            raise ValidationError("changed source attribution")
        copy_verified(source, checked_path(notices, source.name), row["sha256"])
    print(json.dumps({"prepared": "MINTKoreanBackend", "version": manifest["source"]["tag"],
                      "nativeCallMaxUTF16": manifest["linkage"]["nativeCallMaxUTF16"]}))


if __name__ == "__main__":
    try:
        main()
    except (ValidationError, OSError, ValueError, KeyError) as error:
        raise SystemExit("Korean backend preparation failed: " + str(error))
