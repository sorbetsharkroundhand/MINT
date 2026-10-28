# Purlory rename verification — 2026-10-28–29

Scope: full owned application/module/type/script/resource/documentation rename, new `app.purlory.Purlory` identity, `Documents/Purlory`, missing-only legacy preference import, preserved verified manuscript import, and the supplied macOS icon. GitHub repository and origin now use `sorbetsharkroundhand/Purlory`.

## Automated evidence

- `swift build`: passed.
- `swift test`: 1,472 tests, 4 existing skips, zero failures.
- Final focused settings/model/workspace tests after the model-alias correction: 15 tests, zero failures.
- `swift build --product PurloryBench` and benchmark CLI smoke: passed, no model download.
- Offline notice tests: 18 passed; support tests: 9 passed; identity/icon tests: 2 passed; privacy package tests: 2 passed.
- Korean backend validation/preparation tests: 14 and 3 passed.
- Xcode project listing resolves Purlory and PurloryCore; all shell scripts pass syntax checking.
- `scripts/build-purlory-app.sh`: passed, including privacy, all required icon representations, and the 16-dependency/37-component notice inventory. Developer bundle signature verification passed.
- `scripts/smoke-purlory-app.sh`: passed in a disposable home with unique preferences; model-free launch, survival and clean shutdown, no crash.
- `scripts/archive-purlory-app.sh`: passed; unsigned arm64 application identity, executable, icon, fonts, Metal and notice resources verified.
- `scripts/test-purlory-archive-validation.sh`: passed, including the new missing-icon and missing-icon-reference rejection cases.
- `scripts/test-purlory-sandbox-storage.sh`: passed; container writes/reopen and denied external writes.
- `scripts/test-purlory-sandbox-mlx.sh`: passed for valid, missing and corrupt resources; the editor survived resource failure and no model was downloaded.
- Diff whitespace checks and a normalized pre/post-rename source comparison passed review. Third-party source/license bytes and the dependency lockfile remain unchanged.

## Regression findings resolved

The icon-only change allowed an icon in notices but did not require or validate it. Dedicated icon validation now checks the plist reference, ICNS structure, required dimensions, PNG checksums and compressed payloads.

A real Xcode archive proved that `INFOPLIST_KEY_CFBundleIconFile` was not emitted into the generated plist. The first archive correctly failed the new validator. An explicit `Distribution/Purlory-Info.plist` now supplies the icon and application metadata; the rebuilt archive and rejection regressions passed.

Legacy settings tests failed before `PurloryPreferences` existed, then passed with missing-only import, preservation of false values, no repeated import after a reset, no transfer of AI authorization, and no activation of old project references.

## Boundaries

These are working-tree artifacts, stamped with base revision `62f97acdc5698b318b62d5440a2f30d9c5c0376b` and dirty source state, not a frozen release candidate. App Store signing, new App ID configuration, Store submission, native Hangul IME/VoiceOver and final owner acceptance are not claimed.

Existing manuscripts are not automatically relocated across sandbox containers. The verified importer copies a user-selected project or legacy entries folder and preserves the source. Preference-domain access is best-effort across the old/new bundle boundary; see `purlory-upgrade.md`.

Historical benchmark/verification reports retain original artifact identities. Legacy strings remain only where needed to identify old settings/data or historical/upstream material. The active Codex checkout folder remains `Developer/MINT` so the current workspace attachment remains valid; application/build identities do not depend on that directory name.
