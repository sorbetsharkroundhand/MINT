"""Hash-verified, bounded, link-free extraction for the isolated native probe."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import tarfile
import tempfile
import zipfile


class ValidationError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1_048_576):
            hasher.update(block)
    return hasher.hexdigest()


def member_path(name):
    while name.startswith("./"):
        name = name[2:]
    parts = name.split("/")
    if not name or any(p in ("", ".", "..") for p in parts) or "\\" in name or ":" in name:
        raise ValidationError("unsafe path: " + name)
    return name


def checked_path(root, relative):
    relative = member_path(relative)
    path = root
    for part in relative.split("/"):
        path = path / part
        if path.is_symlink():
            raise ValidationError("symlink in staging path: " + relative)
    return path


def entries(path, kind):
    """Yield verified member names and bytes, without using an archive's extractor."""
    total = 0
    seen = set()

    def accept(name, size):
        nonlocal total
        name = member_path(name)
        total += size
        if name in seen or size < 0 or total > 1_073_741_824 or len(seen) >= 10_000:
            raise ValidationError("duplicate or oversized archive member")
        seen.add(name)
        return name

    if kind == "zip":
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                if info.is_dir():
                    member_path(info.filename.rstrip("/"))
                    continue
                mode = info.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValidationError("symlink in archive")
                if stat.S_IFMT(mode) not in (0, stat.S_IFREG):
                    raise ValidationError("special file in archive")
                name = accept(info.filename, info.file_size)
                yield name, archive.read(info)
    elif kind == "tar.gz":
        with tarfile.open(path, "r:gz") as archive:
            for info in archive:
                if info.isdir():
                    if info.name not in (".", "./"):
                        member_path(info.name.rstrip("/"))
                    continue
                if info.issym() or info.islnk():
                    raise ValidationError("symlink or hardlink in archive")
                if not info.isfile():
                    raise ValidationError("special file in archive")
                name = accept(info.name, info.size)
                with archive.extractfile(info) as stream:
                    yield name, stream.read()
    else:
        raise ValidationError("unsupported archive kind")


def checked_archive(root, asset):
    name = member_path(asset["name"])
    if "/" in name:
        raise ValidationError("unsafe path: archive name")
    sha = asset["sha256"]
    if not isinstance(sha, str) or not re.fullmatch("[0-9a-f]{64}", sha):
        raise ValidationError("invalid archive hash")
    path = checked_path(root, "archives/" + name)
    if not path.is_file():
        raise ValidationError("missing archive: " + name)
    if file_digest(path) != sha:
        raise ValidationError("archive hash mismatch: " + name)
    return path


def inventory(root, asset):
    path = checked_archive(root, asset)
    return [{"path": name, "sha256": digest(data), "bytes": len(data)}
            for name, data in entries(path, asset["kind"])]


def verify_inputs(manifest, root):
    if root.is_symlink():
        raise ValidationError("symlink staging root")
    root = root.resolve(strict=True)
    if manifest.get("schemaVersion") != 1 or not manifest.get("assets"):
        raise ValidationError("unsupported or empty artifact manifest")
    checked_path(root, "extracted")
    identities = set()
    for asset in manifest["assets"]:
        identity = member_path(asset["id"])
        if "/" in identity or identity in identities:
            raise ValidationError("duplicate or unsafe artifact identity")
        identities.add(identity)
        expected = {}
        for row in asset["files"]:
            name = member_path(row["path"])
            if name in expected:
                raise ValidationError("duplicate manifest member")
            expected[name] = row
        if not expected:
            raise ValidationError("empty artifact file inventory")
        archive = checked_archive(root, asset)
        actual = inventory(root, asset)
        if {row["path"] for row in actual} != expected.keys():
            raise ValidationError("missing or unrecorded archive member")
        if any(row != expected[row["path"]] for row in actual):
            raise ValidationError("archive file hash or size mismatch")

        destination = checked_path(root, "extracted/" + identity)
        if destination.exists():
            found = set()
            for path in destination.rglob("*"):
                if path.is_symlink():
                    raise ValidationError("symlink in extracted artifact")
                if path.is_file():
                    relative = str(path.relative_to(destination))
                    found.add(relative)
                    row = expected.get(relative)
                    if not row or path.stat().st_size != row["bytes"] or file_digest(path) != row["sha256"]:
                        raise ValidationError("extracted hash mismatch or unrecorded file")
            if found != expected.keys():
                raise ValidationError("missing extracted artifact file")
            continue

        parent = checked_path(root, "extracted")
        parent.mkdir(exist_ok=True)
        staged = Path(tempfile.mkdtemp(prefix=".staged-", dir=parent))
        try:
            for name, data in entries(archive, asset["kind"]):
                target = checked_path(staged, name)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            staged.rename(destination)
        finally:
            if staged.exists():
                shutil.rmtree(staged)
    return {"assets": len(identities), "verification": "artifact-inputs-only"}


def load_manifest(path):
    return json.loads(path.read_bytes())
