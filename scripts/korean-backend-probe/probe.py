"""Build/run the isolated Swift 6 C-ABI probe. Runtime measurements are never invented."""
import json
from contextlib import nullcontext
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

from artifacts import ValidationError, checked_path, file_digest, load_manifest, verify_inputs
from budgets import compare, freeze


def command(argv, log):
    with log.open("w") as stream:
        result = subprocess.run([str(a) for a in argv], stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise ValidationError(f"command failed ({result.returncode}); see {log}")


def fetch_missing(manifest, root):
    root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink():
        raise ValidationError("symlink staging root")
    checked_path(root, "archives").mkdir(exist_ok=True)
    for asset in manifest["assets"]:
        target = checked_path(root, "archives/" + asset["name"])
        if target.exists():
            continue  # Existing corrupt inputs are rejected, never silently replaced.
        expected = "https://github.com/bab2min/Kiwi/releases/download/v0.24.0/" + asset["name"]
        if asset["url"] != expected:
            raise ValidationError("unapproved artifact download URL")
        partial = checked_path(root, "archives/" + asset["name"] + ".partial")
        created = False
        try:
            with partial.open("xb") as output, tempfile.NamedTemporaryFile(
                    prefix=asset["id"] + "-download-", suffix=".log", dir=target.parent,
                    mode="w", delete=False) as errors:
                created = True
                result = subprocess.run(["curl", "--fail", "--location", "--proto", "=https",
                                         "--proto-redir", "=https", "--retry", "2", expected],
                                        stdout=output, stderr=errors, timeout=300)
            if result.returncode or file_digest(partial) != asset["sha256"]:
                raise ValidationError("download archive hash mismatch or transfer failure")
            partial.rename(target)
        finally:
            if created:
                partial.unlink(missing_ok=True)


def native_run(binary, model, output, measure=False, home=None, extra=()):
    context = nullcontext(str(home)) if home else tempfile.TemporaryDirectory(prefix="purlory-korean-home-")
    with context as isolated_home:
        environment = {**os.environ, "CFFIXED_USER_HOME": isolated_home}
        arguments = [str(binary)] + (["--model", str(model)] if model else [])
        arguments += (["--measure"] if measure else []) + list(extra)
        with output.open("w") as stream, output.with_suffix(".stderr.log").open("w") as errors:
            result = subprocess.run(arguments, env=environment, stdout=stream, stderr=errors, timeout=120)
        if result.returncode:
            detail = output.with_suffix('.stderr.log').read_text()[-800:]
            raise ValidationError(f"native probe failed ({result.returncode}); {detail}; see {output.with_suffix('.stderr.log')}")
    return json.loads(output.read_bytes())


def validate_fixtures(result):
    rows = {row["id"]: row for row in result["fixtures"]}
    if result["version"] != "0.24.0" or rows["typo"]["joined"] != "그 일은 어제 됐다." \
            or rows["spacing"]["joined"] != "나는 할 수 있다.":
        raise ValidationError("required real typo/spacing fixture failed")
    if not all(row["utf16RangesValid"] for row in rows.values()):
        raise ValidationError("real UTF-16 range fixture failed")
    if not any(t["original"] == "한글" and t["location"] == 3 and t["length"] == 2
               for t in rows["mixed"]["tokens"]):
        raise ValidationError("emoji-prefixed original offset fixture failed")


def package_resources(app, model, manifest):
    resources = app / "Contents/Resources/KoreanNLP.bundle"
    resources.mkdir(parents=True)
    shutil.copytree(model.parent.parent, resources / "models", dirs_exist_ok=True)
    notices = resources / "Notices"
    notices.mkdir()
    for row in manifest["notices"]:
        source = checked_path(Path.cwd(), row["path"])
        if file_digest(source) != row["sha256"]:
            raise ValidationError("changed source notice")
        shutil.copy2(source, notices / source.name)
    for asset in manifest["assets"]:
        if asset["id"] == "model":
            for row in asset["files"]:
                if file_digest(checked_path(resources, row["path"])) != row["sha256"]:
                    raise ValidationError("packaged model hash mismatch")


def package_checks(args, binary, model, framework_parent, manifest):
    developer = args.output / "DeveloperProbe.app"
    (developer / "Contents/MacOS").mkdir(parents=True)
    shutil.copy2(binary, developer / "Contents/MacOS/KoreanBackendProbe")
    info = {"CFBundleIdentifier": "app.purlory.korean-backend-probe",
            "CFBundleExecutable": "KoreanBackendProbe", "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "14.0", "LSUIElement": True}
    (developer / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    package_resources(developer, model, manifest)
    dev_result = native_run(developer / "Contents/MacOS/KoreanBackendProbe", None,
                            args.output / "developer-bundle.json")
    validate_fixtures(dev_result)
    if not Path(dev_result["modelPath"]).resolve().is_relative_to(developer.resolve() / "Contents/Resources"):
        raise ValidationError("developer resource lookup escaped its bundle")

    archive = args.output / "KoreanBackendProbe.xcarchive"
    command(["xcodebuild", "archive", "-project", "scripts/korean-backend-probe/Probe.xcodeproj",
             "-scheme", "KoreanBackendProbe", "-configuration", "Release",
             "-destination", "generic/platform=macOS", "-archivePath", archive,
             "-derivedDataPath", args.output / "archive-dd", "ARCHS=arm64",
             "KIWI_FRAMEWORK_DIR=" + str(framework_parent), "CODE_SIGNING_ALLOWED=NO",
             "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="], args.output / "archive.log")
    archived_app = archive / "Products/Applications/KoreanBackendProbe.app"
    if (archived_app / "Contents/_CodeSignature").exists():
        raise ValidationError("probe archive is unexpectedly bundle-signed")
    package_resources(archived_app, model, manifest)
    archive_result = native_run(archived_app / "Contents/MacOS/KoreanBackendProbe", None,
                               args.output / "unsigned-archive.json")
    validate_fixtures(archive_result)

    sandbox_app = args.output / "SandboxProbe.app"
    shutil.copytree(archived_app, sandbox_app)
    sandbox_id = "app.purlory.korean-probe." + str(uuid.uuid4())
    sandbox_info = sandbox_app / "Contents/Info.plist"
    info = plistlib.loads(sandbox_info.read_bytes())
    info["CFBundleIdentifier"] = sandbox_id
    sandbox_info.write_bytes(plistlib.dumps(info))
    entitlements = args.output / "sandbox.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
    command(["codesign", "--force", "--sign", "-", "--entitlements", entitlements, sandbox_app],
            args.output / "sandbox-sign.log")
    command(["codesign", "--verify", "--strict", sandbox_app], args.output / "sandbox-verify.log")
    outside = args.output / "outside-synthetic.txt"
    outside.write_text("preserve-this-synthetic-fixture")
    container = Path.home() / "Library/Containers" / sandbox_id
    container.mkdir()  # Collision fails; cleanup owns only this fresh UUID container.
    try:
        home = container / "Data"
        home.mkdir()
        sandbox_result = native_run(sandbox_app / "Contents/MacOS/KoreanBackendProbe", None,
                                    args.output / "sandbox.json", home=home,
                                    extra=["--expect-denied", str(outside.resolve())])
        validate_fixtures(sandbox_result)
        if outside.read_text() != "preserve-this-synthetic-fixture":
            raise ValidationError("sandbox modified the outside fixture")
    finally:
        shutil.rmtree(container / "Data", ignore_errors=True)
        metadata = container / ".com.apple.containermanagerd.metadata.plist"
        try:
            metadata.unlink(missing_ok=True)
            container.rmdir()
        except PermissionError:
            if any(p.name != metadata.name for p in container.iterdir()):
                raise ValidationError("owned sandbox fixture data remains")
    missing = args.output / "missing-model"
    missing.mkdir()
    with tempfile.TemporaryDirectory(prefix="purlory-korean-missing-home-") as home, \
            (args.output / "missing-model.log").open("w") as log:
        result = subprocess.run([str(binary), "--model", str(missing)], stdout=log, stderr=log,
                                env={**os.environ, "CFFIXED_USER_HOME": home}, timeout=120)
    if result.returncode != 2:
        raise ValidationError("missing model did not return a recoverable native error")
    return {"unsignedArchive": True, "sandboxOutsideWriteDenied": True,
            "missingModelRefused": True,
            "packagedBytes": sum(p.stat().st_size for p in archived_app.rglob("*") if p.is_file())}


def run(args):
    if args.output.is_symlink() or (args.output.exists() and any(args.output.iterdir())):
        raise ValidationError("output directory must be empty and not a symlink; choose a fresh evidence path")
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest(args.manifest)
    if manifest["source"]["revision"] != "6e16bbcfc0940fabccbdde574abb4ea3a659588e":
        raise ValidationError("unapproved backend source revision")
    fetch_missing(manifest, args.artifacts_root)
    verify_inputs(manifest, args.artifacts_root)
    framework_parent = (args.artifacts_root / "extracted/native/Kiwi.xcframework/macos-arm64_x86_64").resolve()
    model = (args.artifacts_root / "extracted/model/models/cong/base").resolve()
    binary = (args.output / "KoreanBackendProbe").resolve()
    command(["xcrun", "swiftc", "-swift-version", "6", "-O", "-target", "arm64-apple-macos14.0",
             "-F", framework_parent, "-framework", "Kiwi", "-lc++", "-lz",
             "scripts/korean-backend-probe/main.swift", "-o", binary], args.output / "compile.log")
    result = native_run(binary, model, args.output / "fixtures.json")
    validate_fixtures(result)
    if args.fixtures:
        print(json.dumps({"phase": "native-fixtures", "version": result["version"], "fixtures": len(result["fixtures"])}))
        return
    cold = [result] + [native_run(binary, model, args.output / f"cold-{i}.json") for i in (2, 3)]
    measured = native_run(binary, model, args.output / "measurement.json", measure=True)
    packaging = package_checks(args, binary, model, framework_parent, manifest)
    metrics = {"coldInitializationNS": max(r["initializationNS"] for r in cold),
               "peakResidentBytes": max([r["peakResidentBytes"] for r in cold] + [measured["peakResidentBytes"]]),
               "packagedBytes": packaging["packagedBytes"],
               "cancellationDrainNS": measured["performance"]["cancellation"]["cancellationDrainNS"]}
    for row in measured["performance"]["windows"]:
        metrics[f"warm{row['utf16']}NS"] = row["maxNS"]
        metrics[f"native{row['utf16']}NS"] = row["nativeCallMaxNS"]
    report = {"schemaVersion": 1, "metrics": metrics, "packaging": packaging,
              "nativeCallMaxUTF16": manifest["linkage"]["nativeCallMaxUTF16"],
              "performance": measured["performance"], "coldInitializationsNS": [r["initializationNS"] for r in cold],
              "probeSourceSHA256": file_digest(Path("scripts/korean-backend-probe/main.swift")),
              "manifestSHA256": file_digest(args.manifest),
              "host": {key: subprocess.check_output(command, text=True).strip() for key, command in {
                  "hardware": ["sysctl", "-n", "hw.model"], "memoryBytes": ["sysctl", "-n", "hw.memsize"],
                  "cpu": ["sysctl", "-n", "machdep.cpu.brand_string"], "os": ["sw_vers", "-productVersion"],
                  "swift": ["swift", "--version"], "xcode": ["xcodebuild", "-version"]}.items()}}
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    if args.verify:
        baseline = load_manifest(args.budgets)
        if baseline["probeSourceSHA256"] != report["probeSourceSHA256"]:
            raise ValidationError("changed probe source requires a reviewed new baseline")
        compare(report, baseline)
    else:
        (args.output / "candidate-budgets.json").write_text(json.dumps(freeze(report), indent=2) + "\n")
    print(json.dumps({"phase": "full-probe" if args.probe else "verified", "metrics": metrics,
                      "productionNativeMaxUTF16": 1024}))
