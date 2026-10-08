#!/usr/bin/env python3
"""Write an allowlisted local artifact/environment report, without writer data."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import tempfile
from xml.parsers.expat import ExpatError


def bundle_file(app, relative):
    path = app
    if path.is_symlink():
        raise ValueError("App must not be a symlink")
    for part in relative.split("/"):
        if part in ("", ".", ".."):
            raise ValueError("Noncanonical bundle path")
        path = path / part
        if path.is_symlink():
            raise ValueError("Bundle metadata must not follow symlinks")
    return path if path.is_file() else None


def sha256(path):
    if path is None:
        return None
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def metadata_string(info, key, pattern):
    value = info.get(key)
    if value is not None and (not isinstance(value, str) or not re.fullmatch(pattern, value)):
        raise ValueError("Invalid artifact metadata: " + key)
    return value


def command_value(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def collect(app, model_id=None, model_revision=None, model_state="unknown"):
    model = {"status": "not_collected"}
    if model_id is not None or model_revision is not None:
        if (not isinstance(model_id, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", model_id)
                or ".." in model_id or not isinstance(model_revision, str)
                or not re.fullmatch(r"[0-9a-f]{40}", model_revision)):
            raise ValueError("Model context requires a repository ID and immutable revision")
        if model_state not in {"ready", "loading", "unloaded", "error", "unknown"}:
            raise ValueError("Invalid model state")
        model = {"status": "owner_supplied", "id": model_id, "revision": model_revision, "state": model_state}
    application = {"status": "unavailable", "reason": "missing_bundle_info"}
    info_path = bundle_file(app, "Contents/Info.plist")
    if info_path:
        info = plistlib.loads(info_path.read_bytes())
        if not isinstance(info, dict):
            raise ValueError("Invalid app metadata container")
        executable = metadata_string(info, "CFBundleExecutable", r"[A-Za-z0-9_-]+")
        if not executable:
            raise ValueError("Missing executable identity")
        dirty = info.get("MINTSourceDirty")
        if dirty in ("YES", "NO"):
            dirty = dirty == "YES"
        if dirty is not None and not isinstance(dirty, bool):
            raise ValueError("Invalid source dirty state")
        binary = bundle_file(app, "Contents/MacOS/" + executable)
        application = {
            "status": "available" if binary else "incomplete",
            "bundleIdentifier": metadata_string(info, "CFBundleIdentifier", r"[A-Za-z0-9.-]+"),
            "version": metadata_string(info, "CFBundleShortVersionString", r"[0-9]+(?:\.[0-9]+){0,3}"),
            "build": metadata_string(info, "CFBundleVersion", r"[0-9]+(?:\.[0-9]+){0,3}"),
            "sourceRevision": metadata_string(info, "MINTSourceRevision", r"[0-9a-f]{40}"),
            "sourceDirty": dirty,
            "executableSHA256": sha256(binary),
            "noticesSHA256": sha256(bundle_file(app, "Contents/Resources/ThirdPartyNotices.json")),
        }
    memory = command_value(["/usr/sbin/sysctl", "-n", "hw.memsize"])
    return {
        "schemaVersion": 1, "application": application,
        "environment": {"operatingSystem": platform.system(), "osVersion": platform.mac_ver()[0] or None,
                        "osBuild": command_value(["/usr/bin/sw_vers", "-buildVersion"]),
                        "architecture": platform.machine(),
                        "physicalMemoryBytes": int(memory) if memory and memory.isdecimal() else None},
        "model": model,
        "reproduction": {"status": "owner_required", "steps": [], "expected": "", "actual": ""},
        "privacy": {"excluded": ["manuscripts", "prompts", "project/document titles and paths",
                                 "preferences", "model directories", "logs", "screenshots", "crash reports"]},
    }


def write_report(output, report):
    # /tmp and /var are standard macOS aliases; reject application-created links.
    if any(path.is_symlink() for path in [output, *output.parents] if path not in {Path("/tmp"), Path("/var")}):
        raise ValueError("Support output must not follow symlinks")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, delete=False) as staged:
        temporary = Path(staged.name)
        try:
            staged.write(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
            staged.flush()
            temporary.replace(output)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-id")
    parser.add_argument("--model-revision")
    parser.add_argument("--model-state", choices=["ready", "loading", "unloaded", "error", "unknown"], default="unknown")
    args = parser.parse_args()
    try:
        report = collect(args.app, args.model_id, args.model_revision, args.model_state)
        write_report(args.output, report)
        print("Saved artifact/environment support report; writer data was not collected")
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError) as error:
        parser.exit(1, f"Support collection failed: {error}\n")


if __name__ == "__main__":
    main()
