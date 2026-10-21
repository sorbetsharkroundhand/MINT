# Korean backend validation

## Scope and promotion boundary

Issue [#126](https://github.com/sorbetsharkroundhand/MINT/issues/126), implementation-plan Task 1. This headless executable validates the native dependency before it enters a production target. It does not add proofreading to MINT, change the root package dependencies, select a Ghost LLM, launch MINT or establish Store distribution compliance.

The owner approved the [design](../superpowers/specs/2026-10-15-korean-writing-diagnostics-design.md) and [sequential implementation plan](../superpowers/plans/2026-10-15-korean-writing-diagnostics.md). Task 2 consumes the artifact manifest, measured limits and interface constraints below. The rest of #126 remains open.

## Pinned inputs and reproduction

Kiwi v0.24.0, source `6e16bbcfc0940fabccbdde574abb4ea3a659588e`. The downloaded archives match the release's published SHA-256 digests:

| Archive | Download bytes | SHA-256 |
| --- | ---: | --- |
| `Kiwi.xcframework.zip` | 37,721,249 | `391f948f2e8231bb16449931beba26d055523804f695acc70b79ed6b9dbeb0d7` |
| `kiwi_model_v0.24.0_base.tgz` | 87,967,233 | `33188ba932bba4717bad5244bbec0ef8b1c9cbb47e26e68394a7976d8d779083` |

[artifacts.json](../../Distribution/KoreanBackend/artifacts.json) inventories every archive member and retained notice, source/license provenance, macOS linkage and resource location. The macOS XCFramework slice is a universal **static** library (arm64/x86_64), with a C umbrella module. The selected model directory is `models/cong/base`; the complete extracted model is 109,229,245 bytes. All-platform XCFramework expansion is not the shipping app size.

On an Apple Silicon Mac with Xcode/Swift 6, from the checkout root:

```sh
python3 scripts/test-korean-backend-validation.py
scripts/validate-korean-backend.sh --probe --output build/korean-backend-candidate
scripts/validate-korean-backend.sh --verify --output build/korean-backend-verified
python3 scripts/test-korean-backend-native.py
```

Use a fresh output directory for each run. Nonempty/symlinked output directories are refused so earlier evidence cannot be overwritten. Missing archives are fetched into ignored build staging over HTTPS and checked before extraction; existing corrupt downloads are refused. `--check-inputs` only validates staged archive inputs and does not download or claim native validation. `--fixtures` runs only the real C-ABI fixtures. `--check-metrics <report>` compares recorded metrics; it does not execute the backend again.

The validator rejects traversal, symlinks/hardlinks, special files, duplicate/oversized members, absent/extra files and hash/size changes. Extraction writes regular files through checked paths, never an archive's generic extraction API. Synthetic rejection tests require a positive valid-archive control; a reject-everything validator cannot pass. Frozen-metric tests reject incomplete/nonfinite metrics and budget regressions, including a nonfinite limit that would otherwise bypass comparison.

## Real C-ABI and resource findings

The Swift 6 executable links the published macOS C module with `-target arm64-apple-macos14.0`, libc++ and zlib. Published headers match the exact source C header. The gate builds a developer fixture bundle and a clean unsigned Xcode application archive, copies only verified model/notices resources and executes the archive binary without UI activation. It then ad-hoc signs a disposable copy with App Sandbox, verifies that bundled models remain readable and an ungranted external synthetic write is denied. Removing the model yields a recoverable exit 2. All native subprocesses use `CFFIXED_USER_HOME`; UUID-owned sandbox data is removed afterward. macOS may retain its protected empty container-manager record.

The real fixture suite verifies:

- `그 일은 어제 됬다.` rejoins as `그 일은 어제 됐다.`
- `나는 할수 있다.` rejoins as `나는 할 수 있다.`
- In `🙂 한글 English 42.`, the original `한글` span is UTF-16 location 3, length 2. Every token's range is bounds checked and reconstructed from original UTF-16 units.
- Decomposed Hangul, emoji, mixed scripts, newlines, connective endings and dialect/name examples complete analysis and retain original-coordinate observations.

These are native capabilities, not production diagnostic severity decisions. Full native joining is unsafe as an automatic correction: the ambiguous `장례희망` phrase, English spacing, connective segmentation and invented name `라온이` are changed in these synthetic outputs. NFD input may also rejoin as NFC. Task 6 must use independently validated local morphological/context signatures and exact source spans; it must never replace a whole paragraph with joined text or treat token scores/typo costs as correctness probabilities.

Two integration findings constrain the adapter:

1. Installing the basic typo set through the legacy builder-level parameter reproduced a native SIGSEGV in `Splitter::insertUnkForm`/`splitByTrieUsingTypo`. The exact-source current Swift/C interface instead supports a **prepared typo transformer per analysis**. A plain builder plus `kiwi_typo_prepare(kiwi_typo_get_default(1))` passed the complete fixture and measurement suite. Retain that path and its owned lifetime; the legacy path is not a fallback.
2. The native analyzer emits valid zero-length virtual morphemes, including an elided `이/VCP` in the dialect fixture. They may inform grammar but cannot be marked or replaced in original source.

## Measured baseline and frozen regression limits

[validation-baseline.json](../../Distribution/KoreanBackend/validation-baseline.json) preserves actual Task 1 measurements; [budgets.json](../../Distribution/KoreanBackend/budgets.json) contains the derived limits. Reference host: Apple M2 Max, 32GB, `Mac14,6`, macOS 27.0.1, Swift 6.3.3, Xcode 26.6. The SDK target reports macOS 28; the compile/deployment target is macOS 14. This is not runtime evidence on a macOS 14 installation or on smaller-memory devices.

Each warm size uses five warmups and 30 measured iterations in release optimization. Three fresh processes measure cold initialization; the OS file cache is not forcibly purged. Cold initialization includes builder/model and prepared-typo initialization, not process launch. The performance input is pinned in `main.swift` and the report records its source hash. Values below are maxima, not UI paint timings:

| Metric | Measured maximum | Frozen limit |
| --- | ---: | ---: |
| Cold initialization | 966.38 ms | 1,207.97 ms |
| Warm 256 UTF-16, full adapter observation | 3.45 ms | 4.32 ms |
| Native 256 call | 3.18 ms | 3.98 ms |
| Warm 1,024 UTF-16, full adapter observation | 13.39 ms | 16.74 ms |
| Native 1,024 call | 12.25 ms | 15.31 ms |
| Warm 4,096 UTF-16, full adapter observation | 125.85 ms | 157.31 ms |
| Native 4,096 call | 118.17 ms | 147.72 ms |
| Cancellation to drained 1,024-unit work | 14.42 ms | 18.02 ms |
| Peak resident memory | 869,433,344 bytes | 956,376,679 bytes |
| Unsigned fixture application, resources/notices included | 119,365,573 bytes | 131,302,131 bytes |

Limits are `ceil(1.25 * measured maximum)` for latency and `ceil(1.10 * measured maximum)` for bytes. The fixed 4,096-unit experiment exposes a much longer noninterruptible call. **Production native admission is capped at 1,024 UTF-16 units**, stricter than the approved 4,096 maximum analysis window. The provider must subdivide larger windows and check cancellation/admission before every native call. These measurements permit a short bounded off-main call; they do not prove actual IME/Ghost responsiveness.

Cancellation admits one real call, cancels while it runs and refuses the next queued call. A noncancelled positive control must actually execute both calls. The measured drain includes current synchronous native work; the C call itself is not claimed to be interruptible. Production queue ownership, critical-pressure retirement and cache release still require Task 2/9/10 regressions.

Cold initialization is a separate noninterruptible native operation, approximately 966 ms here with its own 1,208 ms regression ceiling. The 1,024-unit analysis bound does not apply to initialization. Production must admit initialization only after idle policy allows it, run it off-main at utility priority, close queued admission immediately on foreground/pressure changes and retire the initialized handles without analyzing if ownership was lost. Task 2 must test cancellation/critical release during initialization as well as during an analysis call. No editor, save, Ghost or main-actor wait may depend on initialization finishing.

The original probe's native stderr reports that quantization is unsupported for the published binary's `ArchType::none`, followed by a nonquantized fallback. The measured memory and latency include that fallback. Production now selects the same FP32 implementation explicitly through a private constructor adapter using the pinned public C++ headers, since the 0.24.0 C API does not expose `congFp32`. Both `cong.mdl` and `nounchr.mdl` use this selection. The original probe and its evidence remain historical; the adapter change has not been built or executed in the implementation-only UI correction pass. Do not quote the archive size as memory usage or imply that the model is loaded at application startup; production initialization remains lazy and optional.

## Notices and remaining acceptance

The pinned main LICENSE and NOTICE declare Apache-2.0 for Kiwi and the distributed NLP model. The harness packages their text plus pinned component licenses for Eigen (MPL-2.0), cpp-btree, streamvbyte, cpuinfo, mimalloc and JSON. The inventory conservatively follows the upstream library component list. This is reproducible fixture attribution, not proof that all final distribution obligations are fulfilled; #185 remains open, including verification against final bundled artifacts and linked components. Shipping LLM selection and its license audit are separate.

Automatic PR CI exercises the offline rejection suite alongside existing build/test/bench checks. Real native fixtures, package/archive/sandbox execution and reference-host measurements are separately recorded here; a generic CI success is not substituted for them. Actual MINT/IME/VoiceOver/visual verification remains batched under #119 at the owner's requested later stage. No real manuscript, retained app bundle or shipping-LLM cache is used by this probe.

## Production integration follow-through — 2026-10-16

The approved Tasks 2–11 provide verified offline packaging, reversible source/native maps, durable project choices, reviewed correctness/repetition/sentence rules, bounded owned scheduling/reports and safe native corrections. Task 12 connects these prepared values to the editor, Living Margin and project Writing settings; see [production integration](writing-diagnostics-integration.md), [native safety](writing-diagnostics-editor.md), [reports](writing-diagnostics-reports.md) and [incremental scheduling](writing-diagnostics-scheduling.md).

Task 12 repeated the unchanged frozen gate: cold initialization 1.070 s, peak resident 868,810,752 bytes, warm 1,024-unit observation 15.671 ms, cancellation drain 14.646 ms; all limits passed. The retained output is `build/korean-backend-validation/task-12-frozen-verify-20261016`. The later explicit intentional-source proof transfer changes neither backend/resource/worker admission nor these gate inputs. Actual MINT/IME/VoiceOver/paint and Store acceptance remain separate owner-handled gates; #126 stays open until that evidence is available. General grammar completeness and shipping-LLM/device support are not claimed.

Initial Task 12 developer-bundle and unsigned-archive packaging passed from `d31185390b5dde112b722552197a6729ca75239f`, with exact clean-source support provenance, unchanged retained artifacts, 11 new-archive rejection controls and no product launch. Source/artifact digests and the distinction from final native/Store acceptance are recorded in [production integration evidence](writing-diagnostics-integration.md#initial-artifact-evidence-superseded-candidate).

The initial Task 12 package is superseded by final native-load ownership hardening. That bridge-only change does not alter backend/resource/worker or frozen-gate inputs; final clean artifact validation is recorded separately in the production integration evidence.

Final ownership-hardened Task 12 clean packaging passed from `5424a260cd8d38f06fab4a836bfb01e14ec68b8f`: fresh developer/unsigned-archive resources, exact support provenance/privacy checks and all 11 rejection controls against the new archive. Retained artifacts were unchanged. See [final clean artifact evidence](writing-diagnostics-integration.md#final-clean-artifact-evidence). No local product launch was performed.
