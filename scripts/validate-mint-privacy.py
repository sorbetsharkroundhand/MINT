#!/usr/bin/env python3
"""Validate the current MINT-owned declaration, without network or credentials."""
import plistlib
from pathlib import Path
import sys
from xml.parsers.expat import ExpatError

REASONS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"},
    "NSPrivacyAccessedAPICategoryFileTimestamp": {"C617.1", "3B52.1"},
}


def validate(data):
    keys = {"NSPrivacyTracking", "NSPrivacyTrackingDomains",
            "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"}
    if not isinstance(data, dict) or set(data) != keys:
        raise ValueError("unexpected or missing privacy keys")
    if data["NSPrivacyTracking"] is not False:
        raise ValueError("current MINT code does not track users")
    if data["NSPrivacyTrackingDomains"] != [] or data["NSPrivacyCollectedDataTypes"] != []:
        raise ValueError("current MINT code has no tracking domains or collected data")
    apis = data["NSPrivacyAccessedAPITypes"]
    if not isinstance(apis, list):
        raise ValueError("API categories must be an array")
    seen = set()
    for api in apis:
        if not isinstance(api, dict) or set(api) != {"NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"}:
            raise ValueError("invalid API category declaration")
        category, reasons = api["NSPrivacyAccessedAPIType"], api["NSPrivacyAccessedAPITypeReasons"]
        if not isinstance(category, str) or category not in REASONS or category in seen:
            raise ValueError("unknown or duplicate API category")
        if (not isinstance(reasons, list) or not all(isinstance(reason, str) for reason in reasons)
                or len(reasons) != len(set(reasons)) or set(reasons) != REASONS[category]):
            raise ValueError("missing, unknown or duplicate API reason")
        seen.add(category)
    if seen != set(REASONS):
        raise ValueError("missing API category")


def main(app):
    manifest = app / "Contents/Resources/PrivacyInfo.xcprivacy"
    if manifest.is_symlink():
        raise ValueError("privacy manifest must be a bundled file, not a symlink")
    manifest.resolve(strict=True).relative_to(app.resolve(strict=True))
    data = plistlib.loads(manifest.read_bytes())
    validate(data)
    source = Path(__file__).resolve().parent.parent / "Distribution/Resources/PrivacyInfo.xcprivacy"
    if data != plistlib.loads(source.read_bytes()):
        raise ValueError("packaged privacy manifest differs from the current source")
    print("Validated MINT privacy manifest:", manifest)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: validate-mint-privacy.py APP_PATH")
    try:
        main(Path(sys.argv[1]))
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError) as error:
        sys.exit("Privacy validation failed: " + str(error))
