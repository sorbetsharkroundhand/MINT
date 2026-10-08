#!/usr/bin/env python3
"""Build deterministic notices from audited, immutable dependency sources offline."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile


class NoticeError(ValueError):
    pass


def checked_file(root, relative):
    if not isinstance(relative, str) or any(part in ("", ".", "..") for part in relative.split("/")):
        raise NoticeError("Noncanonical notice/resource path")
    root = root.resolve()
    path = root
    for part in relative.split("/"):
        path = path / part
        if path.is_symlink():
            raise NoticeError(f"Symlink notice/resource: {relative}")
    if not path.is_relative_to(root) or not path.is_file():
        raise NoticeError(f"Missing or escaped notice/resource: {relative}")
    return path


def verified_bytes(root, record):
    data = checked_file(root, record["path"]).read_bytes()
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise NoticeError(f"Changed notice/resource: {record['path']}")
    return data


def git(checkout, *args):
    result = subprocess.run(["git", "-C", str(checkout), *args], capture_output=True, text=True)
    if result.returncode:
        raise NoticeError(f"Cannot verify dependency checkout: {checkout.name}")
    return result.stdout.strip()


def collect(repo, checkouts):
    inventory = json.loads((repo / "Distribution/Notices/inventory.json").read_bytes())
    lock = json.loads((repo / "Package.resolved").read_bytes())
    if inventory.get("schemaVersion") != 1 or inventory.get("models") != []:
        raise NoticeError("Unsupported inventory or unapproved model notice set")
    pins = {pin["identity"]: pin for pin in lock["pins"]}
    rows = {row["identity"]: row for row in inventory["packages"]}
    if len(pins) != len(lock["pins"]) or len(rows) != len(inventory["packages"]) or pins.keys() != rows.keys():
        raise NoticeError("Dependency pins and notice inventory differ")
    folders = {}
    for folder in checkouts.iterdir():
        if folder.is_dir() and not folder.is_symlink():
            identity = folder.name.lower()
            if identity in folders:
                raise NoticeError("Ambiguous dependency checkout")
            folders[identity] = folder
    manifest = {"schemaVersion": 1, "packages": [], "components": [], "models": [],
                "resourceBundles": inventory.get("resourceBundles", [])}
    text = ["MINT third-party notices\n\nResolved dependency sources, vendored code and bundled resources.\n"
            "Build-time dependencies are included conservatively. No model weights are included.\n"]

    def read_notices(row, checkout):
        records = row.get("notices")
        if not records:
            raise NoticeError(f"Missing license/attribution: {row['identity']}")
        provenance = row.get("licenseProvenance")
        if any(record.get("root") == "repository" for record in records) and not provenance:
            raise NoticeError("Repository notice override lacks source provenance")
        if provenance:
            if not provenance.get("url", "").startswith("https://") or not re.fullmatch(
                    r"(?:[0-9a-f]{40}|sha256:[0-9a-f]{64})", provenance.get("licenseRevision", "")):
                raise NoticeError("Invalid license provenance")
            for path, expected in provenance.get("coveredGitObjects", {}).items():
                if path.startswith("/") or any(part in ("", ".", "..") for part in path.split("/")):
                    raise NoticeError("Invalid covered source path")
                if git(checkout, "rev-parse", "HEAD:" + path) != expected:
                    raise NoticeError("License provenance no longer covers the pinned source")
            text.append("License source: " + provenance["url"] + "\n")
        for record in records:
            origin = record.get("root", "checkout")
            if origin not in ("checkout", "repository"):
                raise NoticeError("Unknown notice source")
            data = verified_bytes(repo if origin == "repository" else checkout, record)
            content = data.decode("utf-8")
            if not content.strip():
                raise NoticeError("Empty notice")
            text.append(f"\n--- {record['path']} ---\n" + content + "\n")

    for identity in sorted(rows):
        pin, row = pins[identity], rows[identity]
        revision = pin["state"]["revision"]
        checkout = folders.get(identity)
        if checkout is None or row["revision"] != revision or git(checkout, "rev-parse", "HEAD") != revision:
            raise NoticeError(f"Stale/missing dependency source: {identity}")
        if git(checkout, "status", "--porcelain", "--untracked-files=normal"):
            raise NoticeError(f"Modified dependency source: {identity}")
        text.append(f"\n=== {identity} {pin['state'].get('version', '')} ({revision}) ===\n"
                    f"Source: {pin.get('location', '')}\n")
        read_notices(row, checkout)
        manifest["packages"].append({**row, "source": pin.get("location"), "version": pin["state"].get("version")})

    covered = set()
    identities = set()
    for row in inventory["components"]:
        identity, package = row["identity"], row["package"]
        if identity in identities or package not in rows or not row.get("artifacts"):
            raise NoticeError("Duplicate, unowned or empty resource component")
        identities.add(identity)
        checkout = folders[package]
        for artifact in row["artifacts"]:
            verified_bytes(checkout, artifact)
            covered.add((package, artifact["path"]))
        attribution = row.get("attribution", {})
        if row.get("kind") == "font" and not attribution.get("copyright"):
            raise NoticeError("Font copyright attribution missing")
        text.append(f"\n=== {identity} (from {package}) ===\n")
        for key, value in sorted(attribution.items()):
            text.append(f"{key}: {value}\n")
        read_notices(row, checkout)
        manifest["components"].append(row)
    for resource in inventory.get("resourceRoots", []):
        checkout = folders[resource["package"]]
        directory = checkout / resource["path"]
        if directory.is_symlink() or not directory.is_dir() or not directory.resolve().is_relative_to(checkout.resolve()):
            raise NoticeError("Unsafe resource root")
        for path in directory.rglob("*"):
            if path.is_symlink():
                raise NoticeError("Symlink in resource inventory")
            if path.is_file() and (resource["package"], str(path.relative_to(checkout))) not in covered:
                raise NoticeError("Unrecorded distributed resource: " + path.name)
    return manifest, "".join(text)


def output_contents(manifest, text):
    return {"ThirdPartyNotices.json": json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            "ThirdPartyNotices.txt": text}


def validate_app(app, manifest, text):
    resources = app / "Contents/Resources"
    if any(path.is_symlink() for path in [app, app / "Contents", resources]) or not resources.is_dir():
        raise NoticeError("Unsafe or missing app resources")
    allowed = {"PrivacyInfo.xcprivacy", *output_contents(manifest, text)}
    for name, content in output_contents(manifest, text).items():
        if checked_file(resources, name).read_bytes() != content.encode("utf-8"):
            raise NoticeError("Stale/tampered packaged notice: " + name)
    packages = {row["identity"] for row in manifest["packages"]}
    seen = set()
    for bundle in manifest["resourceBundles"]:
        name, package = bundle["name"], bundle["package"]
        if "/" in name or not name.endswith(".bundle") or name in seen or package not in packages:
            raise NoticeError("Invalid resource bundle owner/name")
        seen.add(name)
        root = resources / name
        if not root.exists() and bundle.get("allowMissingInDeveloper"):
            if not checked_file(app, "Contents/MacOS/mlx.metallib").stat().st_size:
                raise NoticeError("Missing developer Metal resource")
            continue
        base = name + ("/Contents/Resources/" if (root / "Contents").is_dir() else "/")
        allowed.update({name + "/Info.plist", name + "/Contents/Info.plist",
                        name + "/Contents/_CodeSignature/CodeResources"})
        prefix = bundle.get("sourcePrefix")
        for component in manifest["components"]:
            if component["package"] == package and prefix:
                for artifact in component["artifacts"]:
                    if artifact["path"].startswith(prefix):
                        relative = base + artifact["path"][len(prefix):]
                        verified_bytes(resources, {**artifact, "path": relative})
                        allowed.add(relative)
        for generated in bundle.get("generated", []):
            relative = base + generated
            if not checked_file(resources, relative).stat().st_size:
                raise NoticeError("Empty generated resource: " + relative)
            allowed.add(relative)
    for path in resources.rglob("*"):
        if path.is_symlink():
            raise NoticeError("Symlink in packaged resources")
        if path.is_file() and str(path.relative_to(resources)) not in allowed:
            raise NoticeError("Unrecorded packaged resource: " + str(path.relative_to(resources)))
    for path in app.rglob("*"):
        if path.suffix.lower() in {".safetensors", ".gguf", ".bin", ".pt", ".pth", ".onnx"}:
            raise NoticeError("Unapproved bundled model artifact: " + path.name)


def write_output(output, manifest, text):
    if output.is_symlink():
        raise NoticeError("Symlink output directory")
    output.mkdir(parents=True, exist_ok=True)
    for name, content in output_contents(manifest, text).items():
        target = output / name
        if target.is_symlink():
            raise NoticeError("Symlink output file")
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output, delete=False) as staged:
            temporary = Path(staged.name)
            try:
                staged.write(content)
                staged.flush()
                temporary.replace(target)
            finally:
                temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkouts", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-app", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    try:
        manifest, text = collect(repo, args.checkouts)
        if args.output:
            write_output(args.output, manifest, text)
        if args.validate_app:
            validate_app(args.validate_app, manifest, text)
        print(f"Notices verified: {len(manifest['packages'])} dependencies, "
              f"{len(manifest['components'])} vendored/resource components, no bundled models")
    except (NoticeError, OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Notice validation failed: {error}\n")


if __name__ == "__main__":
    main()
