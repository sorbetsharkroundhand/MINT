# Privacy Manifest Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. The user explicitly forbids subagents and authorizes continuing without another approval.

**Goal:** Package an audited manifest for current MINT code and reject missing, invalid or stale packaged declarations.

**Architecture:** One canonical `Distribution/Resources/PrivacyInfo.xcprivacy` is copied by the native Xcode resource phase and developer bundle script. A small offline validator checks the packaged plist and compares it with that source. The existing archive gate and app CI invoke the validation; disposable copies exercise rejection.

**Tech Stack:** Xcode resources, plist XML, Python 3 standard library, existing shell build/CI.

**Spec:** [Issue #185](https://github.com/sorbetsharkroundhand/MINT/issues/185), current body retrieved 2026-10-05. This is its independent privacy/resource slice; notices, final model lineup and owner approvals remain open.

## Global Constraints
- Local inference only, no telemetry; no manuscript upload.
- No release model/license approval is inferred from candidate pins.
- Owner checkboxes and final Store/privacy wording remain owner decisions.
- No signing, Store upload, dependency replacement or CI weakening.
- Tests use disposable app resources and do not access manuscripts.

## Review Focus
- A plist bundled elsewhere must not substitute for the root macOS app manifest.
- Malformed types, duplicate categories or unrecorded reason codes must fail.
- A stale packaged declaration must fail even if its XML is valid.
- Symlink escapes must not make external resources appear packaged.
- SDK declarations and host privacy behavior remain separate final release audits.

### Task 1: Package and validate the current app declaration

**Files:** Create `Distribution/Resources/PrivacyInfo.xcprivacy`, `scripts/validate-mint-privacy.py`, `scripts/test-mint-privacy.py`; modify `Distribution/MINT.xcodeproj/project.pbxproj`, `scripts/build-mint-app.sh`, `scripts/validate-mint-archive.sh`, `scripts/test-mint-archive-validation.sh`, `.github/workflows/ci.yml`, `Distribution/README.md`.

**Interfaces:** `validate-mint-privacy.py APP_PATH` exits zero only for a canonical, self-contained current manifest at `Contents/Resources/PrivacyInfo.xcprivacy`. `test-mint-privacy.py APP_PATH` verifies the actual developer artifact and disposable rejection fixtures.

- [x] Add a packaged-resource regression and run it against the existing bundle; expect failure because no app manifest is packaged.
- [x] Audit current app use: app-owned preferences (`CA92.1`); container file metadata (`C617.1`); explicitly selected import metadata (`3B52.1`). Declare no MINT tracking or collected data for the current local-only runtime. Record Apple sources and remaining SDK/model-host audit scope.
- [x] Add the canonical manifest, native Xcode copy wiring and developer bundle copy before signing.
- [x] Implement offline schema/canonical/path checks; add missing, malformed, wrong-type, unknown/duplicate reason, stale and symlink fixture regressions.
- [x] Run resource regressions against the real developer bundle and add them to existing app CI. Extend real archive-copy regressions to remove/tamper the manifest and confirm rejection; preserve all existing archive checks.
- [x] Verify builds/tests and a native archive where available. Inspect its root resources and run existing archive validation tests. No new app behavior requires another interactive UI sweep.
- [ ] Review inline, commit/push/create/attach a bounded PR. Merge the exact reviewed head after required CI; leave #185 open for notice inventory and owner decisions.

References verified against Apple on 2026-10-05:
- [Manifest locations](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [API categories and reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [On-device data and collection](https://developer.apple.com/app-store/app-privacy-details/)
