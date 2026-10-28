# Korean Writing Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver useful offline Korean proofreading, durable author choices and safe explicit corrections in Fiction and General.

**Architecture:** Extend the existing diagnostics engine with a validated native Korean provider. An incremental prose/source/native range index supplies bounded work to an ownership-aware controller; presentation adapters consume prepared findings, while all manuscript and profile mutations retain existing project ownership.

**Tech Stack:** Swift 6, macOS 14+, Foundation, AppKit, SwiftUI, XCTest, pinned Kiwi v0.24.0 C ABI, existing SwiftPM/Xcode packaging and GitHub CI.

**Spec:** [Approved Korean diagnostics design](../specs/2026-10-15-korean-writing-diagnostics-design.md), approved 2026-10-15; code baseline `8a5804e78f0463834e8fbd14498d6fa6cca7df43`.

**Execution selection:** Approved by the owner on 2026-10-15; sequential inline implementation using `superpowers:executing-plans`, without subagents. Retain the existing worktree and small sequential PRs; all required CI passing authorizes merge. Tasks 1–2 merged through PRs #272–#273. Task 3 prose projection/index implementation passed local verification and awaits its required CI/main merge; Tasks 4–12 and final product integration remain pending.

**Task 1 refinement:** The measured published C-ABI path uses a per-analysis prepared typo transformer and admits at most **1,024 UTF-16 units per native call**. The automatic analysis window may still contain up to 4,096 units. Tasks 2/6/9/10 must consume `artifacts.json`'s stricter native cap and subdivide with checked offsets/admission; zero-length virtual morphemes are never editable targets. See [backend validation](../../engineering/korean-backend-validation.md) and the execution ledger for the measured basis.

## Global Constraints

- Editor first; local inference only, no telemetry. Proofreading needs neither an LLM nor network/model setup at runtime.
- Preserve Hangul IME; never generate Ghost during marked text. Preserve Ghost Tab/right-arrow/Esc, focus/selection, cursor-line highlight, Undo, autosave/recovery and Markdown/EPUB/media/math round-trip.
- Generic project/storage code must not depend on Fiction types. Keep Knowledge logic out of `BlockTextView` and `EntryStore`.
- Debounce committed edits for **350 ms**. Automatic requests and native calls contain at most **4,096 UTF-16 units including context**, with at most **256 units of overlap**, on safe grapheme boundaries.
- No whole-document string hashing, Markdown reparsing or native analysis in the keystroke/selection/Ghost path. Full rebuild is load/recovery/global-restyle; foreground work stops new background admission immediately.
- Low/standard/high repetition thresholds are **4/3/2**; off disables the family. Exclude universal `-다` and tense alone. New project defaults: standard repetition, low dialogue; preserve decoded explicit values and the core initializer's standard dialogue value.
- Connective chains require **4 or more clauses**; repeated starts use the first **two lexical forms in three adjacent sentences**; length is **over 120 UTF-16 units**; rhythm uses **three adjacent sentences**.
- Profile key: **`writing-style-profile`**. Durable choices belong to `WritingStyleProfile`, never User Canon or the global macOS dictionary. Unknown/corrupt bytes remain intact.
- Provider ranges address the exact request text. Source, prose and native coordinates are distinct. Duplicate evidence never resolves by selecting the first match; unproved replacements are refused.
- Opaque manuscript, Noto Serif KR body, Pretendard UI, existing palette. Only independently tested, exactly mapped correctness findings receive subtle underlines; style stays advisory.
- English repo documentation/comments; Korean UI and language fixtures are allowed. Logs/support output exclude manuscript excerpts, learned words and prompts by default.
- Keep all existing CI gates. Batch local actual-app/UI checks after implementation; do not launch Purlory during these tasks. Use synthetic data and `CFFIXED_USER_HOME` for native harnesses. Owner selects the shipping LLM later.

## Review Focus

1. Formatting inside a word, emoji and identical paragraphs must never move a correction onto the wrong passage: Tasks 3–4 and 11 test noncontiguous maps and duplicate anchors.
2. An old project's result or profile action arriving after A → B → A must be rejected even when the provider ignores cancellation: Tasks 5 and 9 test runtime generations, not project ID alone.
3. A tiny edit in a huge single paragraph must not trigger a paragraph-sized parse/hash or native call: Tasks 3, 4 and 9 assert visited-input counters on 100k/300k fixtures.
4. Dialect, invented names, decomposed Hangul and quoted rhetoric must remain unchanged: Tasks 6–8 test real tokens, conservative severity and dialogue/learned-word behavior.
5. Missing resources or a failed provider must show unavailable/partial coverage rather than a clean bill of health; native memory release must drain before reuse: Tasks 1–2, 9–10 and 12 cover failures and pressure races.

---

## File boundaries and delivery

Existing foundations remain in place. New files below live under `Sources/PurloryCore/WritingQuality/` unless an exact alternative path is given. Matching test suites live under `Tests/PurloryCoreTests/`; test-only fixtures stay there.

| Unit / files | Responsibility |
| --- | --- |
| `Packages/PurloryKoreanBackend/`, `Distribution/KoreanBackend/`, backend preparation/validation scripts | Pinned native library, verified resources, C bridge, reproducibility and measured promotion gate; no AppKit/MLX dependency. |
| `WritingProseProjection.swift`, `WritingProjectionIndex.swift`; shared scanner in `Editor/MarkdownInlineScanner.swift` | Reversible segment maps and incremental prefix-sum index. Scanner is shared with current inline parsing, not an alternative Markdown grammar. |
| `Editor/BlockTextView+WritingDiagnostics.swift` | Capture committed native changes and mapping metadata; later own safe mutation/decorations. No language rules or NLP. |
| `WritingStyleRecord.swift`, `WritingStyleRepository.swift` | Versioned project choices and runtime-gated writes. |
| `KoreanMorphology.swift`, `KoreanCorrectnessRules.swift`, `KoreanRepetitionRules.swift`, `KoreanSentenceRules.swift`, `KoreanDiagnosticsProvider.swift` | Purlory-owned tokens, pure rules and provider orchestration. |
| `WritingDiagnostics.swift`, `WritingDiagnosticsState.swift`, `WritingDiagnosticsController.swift`, `WritingDiagnosticsCache.swift`, `WritingDiagnosticsReport.swift`, `WritingDiagnosticsRuntime.swift` | Existing engine plus health, ownership, bounded scheduling, memoization, explicit reports and app lifetime. |
| `WritingDiagnosticsPresentation.swift`, `WritingDiagnosticsActions.swift`, `WritingDiagnosticsSettingsView.swift` | Prepared margin values, validated action routing and project preference controls. |

Each numbered task is an independently reviewable PR boundary; split an oversized task only at a working tested seam. No scaffolding-only PR. Task 1 is a reproducible executable backend validation, not a paper audit. Keep #126 open through integration; #270 and #114 retain their remaining work.

All new production types are internal unless required by the `Purlory` executable's composition root; expose only that composition surface. Existing public initializer defaults remain source compatible. Test helpers may have local constructors but are not production APIs.

### Task 1: Prove the pinned backend and freeze promotion budgets

**Files:** Create `scripts/validate-korean-backend.sh`, `scripts/korean-backend-probe/` (isolated Swift 6/C harness), `scripts/test-korean-backend-validation.py`, `Distribution/KoreanBackend/artifacts.json`, `Distribution/KoreanBackend/budgets.json`, `docs/engineering/korean-backend-validation.md`. No root product dependency yet.

**Interfaces:** Consumes exact source `6e16bbcfc0940fabccbdde574abb4ea3a659588e`, published `Kiwi.xcframework.zip` and `kiwi_model_v0.24.0_base.tgz`. Produces `scripts/validate-korean-backend.sh --probe --output <directory>` and `--verify --output <directory>`; exit 0 means all recorded checks passed. `artifacts.json` records source/version, immutable asset URL, SHA-256, architecture/ABI, extracted file hashes, notices and chosen linkage. `budgets.json` records measured baseline, metric units, limits, host/toolchain and fixture hashes.

- [x] **Step 1: Write failing `test_hash_mismatch_escape_missing_model_and_unapproved_artifact_fail_closed`** in `scripts/test-korean-backend-validation.py`. Temporary archive fixtures assert:

  ```python
  self.assertNotEqual(validate("wrong-sha256"), 0)
  self.assertNotEqual(validate("../escaped-model"), 0)
  self.assertNotEqual(validate("symlink-outside-root"), 0)
  self.assertNotEqual(validate("missing-model"), 0)
  self.assertNotEqual(validate("unrecorded-native-file"), 0)
  ```

  `validate(case)` is this suite's subprocess helper for the validator against temporary synthetic manifests/files; no network or real home in rejection tests.
- [x] **Step 2: Run** `python3 scripts/test-korean-backend-validation.py`; expect failure because the verifier is absent.
- [x] **Step 3: Implement the isolated probe/verifier.** Download only into ignored build staging, verify archive SHA-256 before extraction, reject traversal/symlinks and inventory every retained file. Inspect the actual C symbols/headers and Apple Silicon macOS slice. Compile/link with Swift 6 and test resource lookup in a synthetic developer bundle and unsigned sandboxed harness archive without launching Purlory. Prefer the published binary; if its C ABI is unusable, reproducibly build the same exact source and record commands/toolchain/output hashes before repeating every check.
- [x] **Step 4: Run the rejection suite and real `--probe`.** Exercise native morphology, typo candidates and spacing/join behavior on `됬다`, `할수 있다`, `장례희망`, mixed scripts, NFC/NFD Hangul, emoji and multiline inputs. Assert every reported token/candidate range round-trips to its exact original UTF-16 substring; record actual outputs, including absent capabilities. Measure cold load, warm p50/p95/max for 256/1,024/4,096-unit inputs, peak resident memory, packaged bytes, native-call maximum and cancellation-to-no-next-call latency. Never interpret token score/typo cost as a probability.
- [x] **Step 5: Freeze measured limits and verify.** Run 30 warm repetitions after 5 warmups, three cold processes, release optimization and synthetic fixtures on the available 32GB Mac. For each latency metric set the regression limit to `ceil(1.25 * measured maximum)` in its recorded unit; memory/size limit is `ceil(1.10 * measured maximum)`. Record the raw maxima, resulting numbers and an explicit assessment that the measured single-call bound permits foreground yielding. These are regression budgets, not evidence of responsiveness on smaller Macs. If the bound is unacceptable or required typo/spacing evidence cannot be produced, stop backend promotion, document the precise failing gate and repair/reprobe within the approved adapter design; never fill numbers or outcomes speculatively. `--verify` must reproduce artifact/quality checks and meet the frozen limits before Task 2.
- [x] **Step 6: Commit** only the harness, immutable manifests, synthetic fixtures and report: `git commit -m "test: validate pinned Korean morphology backend"`. Record results under #126/#185; all mandatory PR CI remains required. No production success or Store-compliance claim follows from this task alone.

### Task 2: Package a lazy, verified offline native adapter

**Files:** Create `Packages/PurloryKoreanBackend/Package.swift`, `Packages/PurloryKoreanBackend/Sources/CKiwiBridge/`, `Packages/PurloryKoreanBackend/Sources/PurloryKoreanBackend/`, `scripts/prepare-korean-backend.sh`; add `KoreanBackendPackagingTests.swift`. Modify root `Package.swift`, `.gitignore`, `.github/workflows/ci.yml`, `scripts/build-purlory-app.sh`, `scripts/archive-purlory-app.sh`, `scripts/purlory-notices.py`, `scripts/test-purlory-notices.py`, `Distribution/Notices/inventory.json` and `Distribution/Purlory.xcodeproj/project.pbxproj` only as packaging requires.

**Interfaces:** Consumes Task 1's verified manifests and gate. Produces `KoreanNativeWorker(resources: URL)`, `analyze(_ text: String) async throws -> KoreanNativeAnalysis`, `cancelPending()` and `release() async`. `KoreanNativeAnalysis` contains tokens `(form: String, tag: String, range: NSRange)`, sentence ranges `[NSRange]` and correction candidates `(originalRange: NSRange, replacement: String, origin: String)`; ranges address original request text. Define these Sendable values in the adapter, without upstream pointer/POS types or a dependency on PurloryCore. `cancelPending()` synchronously closes queued admission; `release()` drains the admitted call before disposing handles.

- [x] **Step 1: Write failing `testOfflinePackagedResourceAndNativeResult`, `testMissingOrChangedResourceIsUnavailable` and `testReleaseWaitsForAdmittedCall`.** The suite's native test worker asserts:

  ```swift
  XCTAssertEqual(tokens.map { input.substring(in: $0.range) }, expectedOriginalSpans)
  XCTAssertEqual(resourceFailure, .unavailable)
  XCTAssertFalse(openedBeforeFirstAnalyze)
  XCTAssertEqual(callsAdmittedAfterReleaseRequested, 0)
  ```

  Use a controllable C-call seam for drain order, plus the real backend for resource and token tests. Define the substring helper locally with NSString bounds checks.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter KoreanBackendPackagingTests`; expect missing adapter/API failure.
- [x] **Step 3: Implement the validated linkage and resources.** Use the Task 1 binary as a checksum-pinned SwiftPM binary target behind the small C bridge, or its validated exact-source build if that is the recorded gate result. `prepare-korean-backend.sh` fetches/verifies the pinned model into the package's ignored resource directory before builds; it is build preparation only. Track its manifest/resource index, not unbounded generated binaries. Call preparation in CI/developer-bundle/archive entry points before package resolution/build; document the same prerequisite for a clean checkout. Package resources with a dedicated bundle and resolve through that bundle in SwiftPM and Xcode archives. Serialize native work on one off-main worker with a thread-safe admission epoch, checking cancellation/epoch again immediately before each C call. A blocked C call cannot prevent synchronous cancellation of queued calls. Validate all inputs at 4,096 UTF-16 units, preserve original coordinates, and lazily initialize only on admitted analysis.
- [x] **Step 4: Extend resource/notice verification narrowly.** Inventory exact Kiwi/model/linked-component notices and hashes, including Eigen. Keep the LLM model inventory empty; permit only the explicitly inventoried NLP resources at exact paths/hashes. Retain rejection of all unlisted model-like files, tampered files and symlinks; replace inaccurate blanket “no model weights” copy with the actual NLP/LLM distinction. Test verified NLP acceptance plus unlisted `.bin`/`.safetensors` rejection. Run the suite, Task 1 `--verify`, `python3 scripts/test-purlory-notices.py`, clean bundle and unsigned archive validation; expect all passing with resources present offline. No local app launch.
- [x] **Step 5: Commit** `git commit -m "feat: package verified offline Korean backend"` after required build/test/bench checks. Backend availability is not editor integration; no automatic work yet.

### Task 3: Build reversible prose maps and a bounded index

**Files:** Create `WritingProseProjection.swift`, `WritingProjectionIndex.swift`, `Sources/PurloryCore/Editor/MarkdownInlineScanner.swift`, `WritingProseProjectionTests.swift`, `WritingProjectionIndexTests.swift`. Modify `Editor/InlineStyle.swift` to consume shared span scanning; preserve parsing/serialization behavior.

**Interfaces:** Produces Foundation-only `WritingProseBlock` (stable in-session block ID, source/prose text, relative segment map, optional native spans), `WritingProjectionPatch(oldSourceRange: WritingDiagnosticRange, replacement: [WritingProseBlock])`, `WritingAnalysisWindow` (prose text, digest, source segment map, covered range), and `WritingProjectionIndex`. Methods: `reset(source: String)`, `apply(_ patch: WritingProjectionPatch)`, `windows(intersecting: WritingDiagnosticRange) -> WritingAnalysisWindows`, `sourceRanges(for: WritingDiagnosticRange, in: WritingAnalysisWindow) -> [WritingDiagnosticRange]?`, `sourceRanges(forProse: WritingDiagnosticRange) -> [WritingDiagnosticRange]?` for absolute report spans. `WritingAnalysisWindows: Sequence` lazily yields immutable windows over a revision-frozen piece index; it never materializes an entire huge edit. `WritingWindowSplitter.ranges(in text: String) -> AnySequence<WritingDiagnosticRange>` supplies the same bounded split/overlap policy for already-projected request text. Source/prose/native segments use relative UTF-16 ranges and an eligibility flag; index prefix sums provide absolute offsets.

- [x] **Step 1: Write failing `testProseExclusionsAndReversibleOffsets`, `testDuplicateFormattedAndEmojiSpans` and `testHugeParagraphSpliceVisitsBoundedInput`.** Fixture: headings/lists, emphasis inside `할**수**`, inline code, links with visible labels, font/alignment wrappers, fenced code, images, inline/display math, duplicate prose and `🙂한`. Assert:

  ```swift
  XCTAssertEqual(mappedOriginalSubstrings, expectedEligibleSubstrings)
  XCTAssertNil(contiguousReplacementAcrossMarkup)
  XCTAssertEqual(excludedCodeMathMediaDestinationFindings, 0)
  XCTAssertLessThanOrEqual(maxWindowUTF16, 4096)
  XCTAssertLessThanOrEqual(maxOverlapUTF16, 256)
  XCTAssertEqual(brokenGraphemeBoundaries, 0)
  ```

  On synthetic 100k/300k text and a 300k single paragraph, insert one character using a known patch; assert no reset/full hash, changed scan ≤4,096 plus bounded neighbor windows, and unchanged suffix positions match a full reference rebuild.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'WritingProseProjectionTests|WritingProjectionIndexTests'`; expect missing index/map failure.
- [x] **Step 3: Implement map/index methods.** Extract source-span scanning from current inline semantics, keeping AppKit attributes in `InlineStyle.swift`. Use indexed block/piece prefix sums and per-window digests; reuse `ParagraphRenderIndex` mechanics without confusing native/source coordinates. Maintain subparagraph pieces so one oversized paragraph is never reparsed as a unit on ordinary edits. Exclude ineligible runs; retain disjoint source segments for inspection but allow replacement only on a proved contiguous eligible run. Propagate edits to intersecting/related findings and bounded adjacent sentence context. Scan multi-block edits through cancellable chunks; fallback reset only for documented load/recovery/global-restyle events, not “unknown edit” on each keystroke.
- [x] **Step 4: Run** these suites plus existing inline/serialization regressions (`swift test --disable-automatic-resolution --filter 'WritingProse|WritingProjection|Inline|Serialization'`); expect exact round-trip and bounded counters passing.
- [x] **Step 5: Commit** `git commit -m "feat: index reversible prose analysis windows"`.

### Task 4: Capture native mapping and committed edit deltas

**Files:** Extend `Editor/BlockTextView+WritingDiagnostics.swift` (create now), narrowly modify `Editor/BlockTextView.swift` coordinator/load/serialization hooks and `ContentView.swift`'s `ProjectEditorBridge`; add `WritingEditorProjectionTests.swift`.

**Interfaces:** Consumes Task 3 blocks/patches. Produces `WritingEditorCommit(baseIdentity: ProjectRuntimeIdentity, nativeRevision: UInt64, patch: WritingProjectionPatch, markedRange: WritingDiagnosticRange?)`, emitted after the existing binding publishes committed source. `BlockTextView.writingNativeRevision: UInt64`, `writingCommitDidChange: ((WritingEditorCommit) -> Void)?`, `writingCompositionDidChange: ((WritingDiagnosticRange?) -> Void)?`, and `nativeRange(forSource: WritingDiagnosticRange, revision: UInt64) -> WritingDiagnosticRange?`. Keep language analysis outside the editor.

- [x] **Step 1: Write failing `testLoadAndNativeEditMapsMatchCanonicalSource`, `testIMEIsNeverCommittedForDiagnostics`, `testHugeParagraphDeltaDoesNotReserializeForDiagnostics`, `testUndoRedoAndProgrammaticChangesEmitValidPatches`.** Use inert NSTextStorage/NSTextView and test UndoManager, without showing Purlory:

  ```swift
  XCTAssertEqual(nativeSubstring, expectedOriginal)
  XCTAssertEqual(diagnosticsTriggeredUnmarkCount, 0)
  XCTAssertEqual(committedAnalysisEventsDuringMarkedText, 0)
  XCTAssertEqual(additionalWholeDocumentSerializations, 0)
  XCTAssertEqual(sourceAfterApplyingPatches, editor.serialize())
  ```

  Include newline joins/splits, paste, block marker conversion, formatting-only edits, duplicate paragraphs, media/math attachments and 300k single-paragraph insertion. Existing serialization may assemble the binding value; diagnostics must not add another full comparison/hash/parse.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter WritingEditorProjectionTests`; expect missing hooks/map failure.
- [x] **Step 3: Implement passive hooks.** Capture before/after deltas at existing storage/serialization seams, share cached block serialization metadata and source-span scanning, and attach native ranges only when verified against the current storage revision. Increment native revision for character and mapping-affecting attribute changes. Pair the commit with the authoritative post-binding project snapshot; a source snapshot arriving before its native delta remains pending. Composition notifications cancel work/marks without changing IME. An untracked programmatic edit must capture its affected storage range; it cannot silently masquerade as a cheap local patch or reuse an old map. Avoid widening unrelated private math state.
- [x] **Step 4: Run** the suite plus `EditorRenderIndexTests`, `SerializationFuzzTests`, `ProjectEditorTransitionTests` and existing IME/Ghost tests; expect no content/selection/Undo regression and no extra document pass.
- [x] **Step 5: Commit** `git commit -m "feat: capture revisioned editor prose changes"`.

**Implementation boundary:** Native/source row prefix totals are separate; mapping requires current runtime/revision, exact original UTF-16 and whole composed characters. Literal edits inherit proved grammar scopes from bounded cached source pieces. Structural/paste edits reuse the existing serializer's row strings in yielding, cancellable pieces, without another document serialization, parse or hash. A raw reference that cannot be proved within a deferred piece is explicitly unsupported through its line, and following lines resume; Tasks 9/10 must expose that partial coverage. Profile-only snapshot adoption verifies unchanged source at that explicit transition; ordinary binding snapshots stay pending until their native commit arrives.

### Task 5: Persist project style choices without replacing unreadable data

**Files:** Create `WritingStyleRecord.swift`, `WritingStyleRepository.swift`, `WritingStyleRepositoryTests.swift`; reuse existing `WritingStyleProfile`, `ProjectSession.updateUserData` and recovery fixtures.

**Interfaces:** `WritingStyleRecord` version 1 contains `profile: WritingStyleProfile`, `languageTag: String?`, and `[WritingIntentionalOccurrence]` (rule ID, `EvidenceAnchor`, captured source revision). `WritingStyleLoad` is `.ready(WritingStyleRecord)` or `.unreadable(original: Data, reason: String)`. `WritingStyleRepository.read(_ snapshot: ProjectDocumentSnapshot) -> WritingStyleLoad`; `update(_ record: WritingStyleRecord, in session: ProjectSession, identity: ProjectRuntimeIdentity) throws`. Both repository entry points are MainActor. Missing record uses standard/low; value-only legacy profiles decode preserving explicit standard/standard. Learned words use canonical Unicode composition and exact lexical comparison, without lowercasing unrelated scripts or modifying source.

- [x] **Step 1: Write failing `testNewLegacyUnknownAndCorruptProfiles`, `testChoicesSurviveFlushReopenReindexAndRestore`, `testStaleAtoBtoAActionCannotWrite`.** Assert:

  ```swift
  XCTAssertEqual(newRecord.profile.dialogueSensitivity, .low)
  XCTAssertEqual(decodedLegacy.profile.dialogueSensitivity, .standard)
  XCTAssertEqual(unreadableBytesAfterReadAndFailedUpdate, originalBytes)
  XCTAssertEqual(restoredRecord, savedRecord)
  XCTAssertEqual(bProjectBytesAfterStaleAction, bProjectBytesBefore)
  ```

  Include failed save, runtime transition, no-op update, two occurrences with identical quotes, and a changed ambiguous source which must not inherit occurrence suppression. Reuse temporary-project backup/recovery harnesses; no second storage owner.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter WritingStyleRepositoryTests`; expect absent envelope/repository failure.
- [x] **Step 3: Implement decoding and gated writes.** Use safe key `writing-style-profile`, existing autosave and recovery. Refuse normal updates while unreadable bytes exist; reading never writes defaults. Resolve intentional choices against captured evidence/current occurrence, using `SourceAnchor` for explicit re-anchoring and declining ambiguity. Compute a whole-source revision only for deliberate capture/re-anchor/load operations, never each automatic edit. Learned words and ignored rules stay project owned and survive derived-index deletion.
- [x] **Step 4: Run** the new suite plus `ProjectUserDataTests`, `ProjectUserDataSessionTests`, existing backup/recovery suites and `WritingDiagnosticsTests`; expect preserved bytes, defaults and ownership.
- [x] **Step 5: Commit** `git commit -m "feat: persist project writing style choices"`.

### Task 6: Add real morphology and conservative correctness findings

**Files:** Create `KoreanMorphology.swift`, `KoreanCorrectnessRules.swift`, `KoreanDiagnosticsProvider.swift`, `KoreanCorrectnessTests.swift`, `Tests/PurloryCoreTests/Fixtures/KoreanDiagnostics/correctness.json` (synthetic reviewed cases).

**Interfaces:** `KoreanMorphology(worker: KoreanNativeWorker)` and `analyze(_ text: String) async throws -> KoreanAnalysis` adapt Task 2's native values. `KoreanAnalysis` contains `text: String`, `[KoreanToken]` (form/tag/range), sentence ranges and correction candidates (originalRange/replacement/origin), converting NSRange to validated `WritingDiagnosticRange` at this boundary. `KoreanCorrectnessRules.evaluate(_ analysis: KoreanAnalysis, profile: WritingStyleProfile) -> [WritingDiagnostic]`. `KoreanDiagnosticsProvider(morphology: KoreanMorphology): WritingDiagnosticsProvider` implements existing `analyze(_:)`; `id = "ko.kiwi.v0.24.0"`. Rule revision is an explicit cache-key input, starting at 1.

- [x] **Step 1: Write failing real-provider `testUnambiguousTypoAndMorphologicalSpacing`, `testAmbiguousFictionAndLearnedNamesRemainSuggestionsOrQuiet`, `testMixedAndDecomposedOffsetsStayOriginal`.** Assert:

  ```swift
  XCTAssertEqual(typo.alternatives, ["됐다"])
  XCTAssertEqual(spacing.alternatives, ["할 수 있다"])
  XCTAssertEqual(typo.severity, .correctness)
  XCTAssertFalse(ambiguousFindings.contains { $0.severity == .correctness })
  XCTAssertTrue(learnedNameFindings.isEmpty)
  XCTAssertEqual(originalSubstringAtEveryFinding, expectedSubstrings)
  ```

  Pin complete positive/negative contexts, not the isolated substring `수`. Include `됬다`, morphology-confirmed `할수 있다`, `장례희망`, proper names, dialect, literary spelling, emoji prefixes, mixed English and NFC/NFD equivalents. No fixture provider may satisfy this suite.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter KoreanCorrectnessTests`; expect missing production provider or required detections.
- [x] **Step 3: Implement native candidate conversion and explicit eligibility rules.** Derive alternatives from verified native typo/spacing/join operations; permit inline severity only for reviewed unambiguous morphological/context signatures with exact original spans. Keep uncertain candidates advisory/quiet, confidence nil unless independently calibrated, and unsupported-language spans quiet. Do not implement a suffix/string replacement list as a purported Korean analyzer. Preserve normalized lookup-to-original offset mapping and apply learned-word suppression to lexical entries, not arbitrary substrings. Invalid provider ranges are rejected, not clamped into unrelated prose.
- [x] **Step 4: Run** the real suite and Task 1 verification. Record fixture outcomes separately from orchestration tests; expect required positives, no automatic ambiguous-fiction errors and exact original ranges.
- [x] **Step 5: Commit** `git commit -m "feat: detect conservative Korean spelling and spacing issues"`.

### Task 7: Detect morphological repetition with evidence

**Files:** Create `KoreanRepetitionRules.swift`, `KoreanRepetitionTests.swift`, `Tests/PurloryCoreTests/Fixtures/KoreanDiagnostics/repetition.json`; extend provider composition from Task 6.

**Interfaces:** `KoreanRepetitionRules.evaluate(_ analysis: KoreanAnalysis, profile: WritingStyleProfile) -> [WritingDiagnostic]`. Stable IDs: `ko.style.repeated-word`, `ko.style.repeated-particle`, `ko.style.repeated-ending`, `ko.style.repeated-connector`. Produces suggestion severity, primary plus related original ranges, Korean explanations and no unsolicited rewrite.

- [x] **Step 1: Write failing `testInflectedFamiliesAndHomographs`, `testSensitivityAndDialogueMatrix`, `testParagraphBoundaryAndIntentionalRepetition`.** Real tokens for `-는데`, causal `-아서/-어서/-여서`, particles and connectors; assert:

  ```swift
  XCTAssertEqual(requiredOccurrencesBySensitivity, [4, 3, 2])
  XCTAssertTrue(offFindings.isEmpty)
  XCTAssertEqual(standardThreeOccurrenceFinding.relatedRanges.count, 2)
  XCTAssertTrue(universalDaAndTenseOnlyFindings.isEmpty)
  XCTAssertTrue(particleHomographFalsePositives.isEmpty)
  XCTAssertTrue(separateParagraphRepetition.isEmpty)
  ```

  New-profile quoted dialogue needs four occurrences; explicit old standard needs three; off suppresses dialogue style but not correctness. Cover nested Korean/ASCII quotes, rhetorical repetition, and actual occurrence explanations. Intentional suppression is applied with Task 5 ownership, not inferred from text.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter KoreanRepetitionTests`; expect absent style findings.
- [x] **Step 3: Implement grammatical-family normalization and bounded adjacent occurrence grouping.** Use native POS and clause/sentence context, not suffix-only matching. Maintain original spans for every family occurrence and aggregate one pattern rather than overlapping warnings. Preserve paragraph boundaries and dialogue sensitivity; correctness policy stays independent.
- [x] **Step 4: Run** the suite and `KoreanCorrectnessTests`; expect exact threshold matrix, evidence and quiet negatives.
- [x] **Step 5: Commit** `git commit -m "feat: detect Korean morphological repetition"`.

### Task 8: Add sentence flow rules and chunk-independent report state

**Files:** Create `KoreanSentenceRules.swift`, `KoreanSentenceRulesTests.swift`, `Tests/PurloryCoreTests/Fixtures/KoreanDiagnostics/sentence-flow.json`; extend provider internals.

**Interfaces:** `KoreanRuleSession(profile: WritingStyleProfile)`; `consume(_ analysis: KoreanAnalysis, proseOffset: Int, final: Bool) -> [WritingDiagnostic]`; `reset()`. Session composes correctness/repetition/flow, belongs to one request/report, and returns ranges relative to the entire exact request text. Add `KoreanDiagnosticsProvider.analyzeChunks(_ request: WritingDiagnosticsRequest, emit: @escaping @Sendable (KoreanDiagnosticsChunk) async throws -> Void) async throws`. `KoreanDiagnosticsChunk` contains diagnostics, assessed prose range and total prose UTF-16 length. Existing `analyze(_:)` collects this pipeline; `.document` internally splits using Task 3's splitter, while `.local` is already bounded. Stable new IDs: `ko.style.redundant-causality`, `ko.style.connective-chain`, `ko.style.repeated-sentence-start`, `ko.style.sentence-length`, `ko.style.sentence-rhythm`.

- [x] **Step 1: Write failing `testCausalTransitionChainStartAndLengthBoundaries`, `testChunkBoundaryDoesNotChangeReport`, `testSessionResetCannotLeakQuoteOrPatternState`.** Assert:

  ```swift
  XCTAssertEqual(chainFindingCountsForThreeAndFourClauses, [0, 1])
  XCTAssertEqual(lengthFindingCountsFor120And121UTF16, [0, 1])
  XCTAssertEqual(startFindingFirstTwoLexicalForms, ["그", "사람"])
  XCTAssertEqual(threeSentenceRhythmFindings.count, 1)
  XCTAssertEqual(chunkedCanonicalFindings, singlePassCanonicalFindings)
  XCTAssertTrue(nextProjectFindings.isEmpty)
  ```

  Put the causal ending/`그래서`, repeated starts and rhythm sequence across every relevant chunk boundary, including a long sentence crossing 4,096 units. Validate rhetorical/dialogue negatives and reason/evidence for each rule. Single-pass reference is a pure-rule test, not an oversized native call.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter KoreanSentenceRulesTests`; expect missing flow/session implementation.
- [x] **Step 3: Implement bounded streaming rule state.** Carry at most the threshold's recent occurrence records, first two lexical forms, three sentence-pattern summaries, current clause count/range and quote state; store digests/ranges instead of accumulating sentence text. Overlap ownership emits each occurrence once. Reset on cancellation/profile/document revision. Flow findings are suggestions; length/rhythm aggregate as info. Reject context-free causal guesses.
- [x] **Step 4: Run** the suite and all Korean rule suites; expect boundary-independent output and bounded retained state on a 300k single paragraph.
- [x] **Step 5: Commit** `git commit -m "feat: analyze Korean sentence flow across bounded chunks"`.

### Task 9: Schedule incremental work with health and publication ownership

**Files:** Create `WritingDiagnosticsState.swift`, `WritingDiagnosticsController.swift`, `WritingDiagnosticsCache.swift`, `WritingDiagnosticsControllerTests.swift`; extend `WritingDiagnostics.swift` and its engine tests without changing provider protocol.

**Interfaces:** Extend `WritingDiagnosticsSnapshot` with defaulted `[WritingProviderOutcome]` (`providerID`, status success/failed/unavailable; no excerpt-bearing error payload). `WritingDiagnosticsStamp` contains runtime identity, native revision, profile revision, provider/rule revision and window digest. `WritingDiagnosticsFinding` wraps diagnostic, project/document ownership, source/related spans, EvidenceAnchor and stamp. `WritingDiagnosticsCoverage` contains assessed/dirty/pending source ranges and `isComplete: Bool`; `WritingDiagnosticsAvailability` distinguishes available, unsupported language, unavailable resource/provider/profile and paused policy. `WritingDiagnosticsState` contains findings, coverage, availability and status idle/checking/partial/unavailable/paused. Define `WritingDiagnosticsClock: Sendable` with `sleep(for: Duration) async throws`. MainActor ObservableObject `WritingDiagnosticsController.init(engine: WritingDiagnosticsEngine, clock: any WritingDiagnosticsClock, currentSnapshot: @escaping @MainActor () -> ProjectDocumentSnapshot?)` exposes `state`, `noteSnapshot(_ snapshot: ProjectDocumentSnapshot)`, `noteEditorCommit(_ commit: WritingEditorCommit, snapshot: ProjectDocumentSnapshot)`, `setForegroundBusy(_ busy: Bool)`, `setMarkedRange(_ range: WritingDiagnosticRange?)`, `setMemoryPressure(_ level: MemoryPressureLevel)`, `setEnergyPolicy(thermal: ProcessInfo.ThermalState, lowPower: Bool)`, `cancel()`. The controller obtains the record through Task 5's repository; missing/corrupt data keeps the defined semantics.

- [x] **Step 1: Write failing `test350msDebounceAndBoundedDirtyCoverage`, `testLateProviderAndLocalReportCannotPublishAcrossGenerations`, `testProviderFailureIsNotClean`, `testWindowMemoAndCacheEviction`.** Controlled clock/provider barriers assert:

  ```swift
  XCTAssertEqual(callsAfter349ms, 0)
  XCTAssertEqual(callsAfter350ms, 1)
  XCTAssertLessThanOrEqual(maxRequestUTF16, 4096)
  XCTAssertEqual(stalePublishedFindings, 0)
  XCTAssertEqual(failedState.status, .unavailable)
  XCTAssertFalse(failedState.assessedCoverageContainsFailedRange)
  XCTAssertEqual(unchangedWindowAdditionalCalls, 0)
  ```

  Exercise uncancellable native/provider completion, edit bursts, A → B → A, same-text userData generation changes, profile/rule revision changes, invalid primary/related ranges, active composition, 100k/300k and huge-paragraph edits. Preserve unaffected findings but immediately remove dirty/related stale occurrences.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'WritingDiagnosticsControllerTests|WritingDiagnosticsTests'`; expect missing health/controller and new failure assertions.
- [x] **Step 3: Implement health-aware engine results and controller.** Preserve legacy `analyze(_:)` and default initializer compatibility; normalize only valid findings, checking NSNotFound, negative/overflowing and out-of-bounds primary/related ranges before conversion. Pair source snapshot and post-binding native patch before publishing native eligibility. Check the whole stamp after every await; an engine generation alone is insufficient. Map provider ranges through Task 3 before source publication. Cache only active-document windows, keyed by digest plus language/profile/provider/rule revisions. Use a **16 MiB** byte-accounted LRU for reconstructible input/result caches and a separate **16 MiB** active-finding/evidence budget; report partial coverage when a result budget is exhausted. Generate occurrence IDs from rule/document identity plus anchored occurrence discriminator, preserving unaffected IDs through index splices; identical quotes remain distinct. Metadata-only generation updates may reuse unchanged analysis while rebinding current authority through unchanged native revision/commit metadata, without comparing whole bodies. No whole-document hashing/copying is added to the edit callback.
- [x] **Step 4: Run** both suites, real Korean suites and deterministic bounded-visit tests. Expect no admission during typing/Ghost/marked text, correct pending/failed coverage, no cross-project publication and byte-budget eviction. Cancellation tests use barriers, not timing sleeps.
- [x] **Step 5: Commit** `git commit -m "feat: schedule owned incremental writing diagnostics"`.

### Task 10: Share pressure admission and expose explicit full reports

**Files:** Create `WritingDiagnosticsReport.swift`, `WritingDiagnosticsRuntime.swift`, `WritingDiagnosticsReportTests.swift`, `WritingDiagnosticsPressureTests.swift`; modify `Inference/MemoryPressureRuntime.swift`, `Inference/MemoryPressureCoordinator.swift`, `ContentView.swift` consumer composition and `Sources/Purlory/PurloryApp.swift` lifetime wiring. Preserve existing completion/indexer callbacks.

**Interfaces:** `WritingDiagnosticsController.scanDocument(_ snapshot: ProjectDocumentSnapshot) -> WritingDiagnosticsReport` and `cancelReport()`. `WritingDiagnosticsReport: AsyncSequence` yields `WritingDiagnosticsReportEvent` through a one-event bounded asynchronous channel. Events carry runtime/profile ownership and `.progress(completed: Int, total: Int)`, `.findings([WritingDiagnosticsFinding])`, `.finished(WritingDiagnosticsCoverage)`, `.cancelled`, `.failed(WritingDiagnosticsAvailability)`, using Task 9 values. A project scan iterates immutable document snapshots through this API; no implicit project disk scan. Reports use Task 8's `analyzeChunks` with a private request/session and lower-priority admission over the same serial native worker, independent of the local engine generation. Public MainActor ObservableObject `WritingDiagnosticsRuntime.init()` owns the internal controller/repository/worker; `prepareForTermination() async` drains release. Pass this runtime into `ContentView` and add a defaulted optional runtime parameter to `MemoryPressureRuntime` to preserve existing callers. Its internal `setMemoryPressure(_ level: MemoryPressureLevel)` forwards warning/critical levels and waits for native release without blocking the main actor.

- [x] **Step 1: Write failing `testReportProgressCancelAndLateLocalRace`, `testCriticalDrainThenNormalCannotReopenOldWorker`, `testForegroundThermalAndLowPowerStopAdmission`.** Assert:

  ```swift
  XCTAssertTrue(progressIsMonotonicAndMatchesAssessedCoverage)
  XCTAssertEqual(nativeCallsAfterForegroundOrCancellation, 0)
  XCTAssertEqual(lateReportOverwritesOfLocalState, 0)
  XCTAssertFalse(resumedBeforeNativeReleaseDrained)
  XCTAssertTrue(completionAndIndexerStillReceivePressure)
  ```

  Block one native call, request critical release then normal, change project/profile and finish the old call; no new work may begin for the old owner. Warning evicts derived caches and pauses scans; serious/critical thermal or Low Power pauses optional analysis. Recovery reschedules only current dirty work after idle policy permits.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'WritingDiagnosticsReportTests|WritingDiagnosticsPressureTests|MemoryPressure'`; expect missing report/pressure composition.
- [x] **Step 3: Implement report and runtime integration.** Capture immutable source/profile once, chunk at 4,096 with ≤256 overlap, use Task 8's private report session and stream mapped results/progress. Count progress in eligible prose UTF-16 units, excluding overlap; total comes from index sums. Await channel capacity before admitting the next chunk; a slow consumer cannot accumulate manuscript-sized pending events. Cancel a report when its consumer terminates, and wake blocked sends on cancellation. Add a slow-consumer test asserting at most one queued event and no subsequent chunk admission. No late report can replace local current coverage. Admit no next chunk after cancellation/foreground/pressure; release worker after the admitted C call drains within Task 1's measured bound. Critical release clears reconstructible resources only; preserve profile and manuscript. Integrate with existing single monitor and completion-busy callback by composition, not assignment that drops consumers. No Review placeholder UI or model selection is introduced.
- [x] **Step 4: Run** report/pressure and existing completion/indexer memory suites, Task 1 `--verify` and chunk-equivalence fixtures. Expect bounded memory and cancellation latency within frozen limits.
- [x] **Step 5: Commit** `git commit -m "feat: expose cancellable writing reports and pressure control"`.

### Task 11: Draw restrained marks and apply one validated native edit

**Files:** Extend `Editor/BlockTextView+WritingDiagnostics.swift`; narrowly modify `PurloryLayoutManager` drawing in `Editor/BlockTextView.swift`; create `WritingDiagnosticsActions.swift`, `WritingDiagnosticsEditorTests.swift`, `WritingDiagnosticsDecorationTests.swift`.

**Interfaces:** MainActor `BlockTextView.setWritingDiagnostics(_ findings: [WritingDiagnosticsFinding], revision: UInt64)`; `applyWritingCorrection(_ correction: WritingCorrection, identity: ProjectRuntimeIdentity) -> WritingCorrectionResult`. `WritingCorrection` carries finding/stamp, exact expected source/native text and replacement. Result is `.applied` or `.refused(reason: WritingCorrectionRefusal)`; refusal cases stale/composing/unmapped/ambiguous/formatting. `WritingDiagnosticsActions.apply(findingID: String, alternativeIndex: Int) -> WritingCorrectionResult` resolves only current controller values and current project/editor ownership.

- [x] **Step 1: Write failing `testCorrectionIsOneUndoableEdit`, `testRefuseStaleDuplicateFormattedAndMarkedTargets`, `testDecorationNeverMutatesStorageOrOtherLayers`.** Assert:

  ```swift
  XCTAssertEqual(afterCorrection, expectedMarkdown)
  XCTAssertEqual(afterOneUndo, originalMarkdown)
  XCTAssertEqual(afterRedo, expectedMarkdown)
  XCTAssertEqual(refusedSourceAfter, refusedSourceBefore)
  XCTAssertTrue(editor.hasMarkedText())
  XCTAssertEqual(attributesAfterMarkAndClear, authorAttributesBefore)
  XCTAssertEqual(serializedAfterDecoration, serializedBeforeDecoration)
  ```

  Include duplicate quotes after unrelated edits, emoji, mixed format runs inside a word, media/math neighbors, stale alternatives, project transitions, selection/search/current-line/Ghost coexistence, autosave event emission and focus/caret after success. Retain Ghost key behavior tests; diagnostic controls add no editor key interception.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'WritingDiagnosticsEditorTests|WritingDiagnosticsDecorationTests'`; expect missing native action/decoration methods.
- [x] **Step 3: Implement native presentation and mutation.** Store diagnostic marks outside NSTextStorage attributes; draw only visible mapped correctness runs through a separate layout drawing helper using existing palette contrast. Clear/withhold overlapping marks during composition; never force unmark. Validate current runtime/native/source map, exact substring and uniform eligible formatting immediately before mutation. Call existing `shouldChangeText`/native replacement/`didChangeText` path inside one undo group, preserving formatting and normal autosave serialization. Refuse and schedule recheck when any proof fails. Return focus to the same editor with caret after replacement; no document reload.
- [x] **Step 4: Run** the suites plus serialization/media/math, Ghost, project transition and recovery regressions. Measure visible decoration cost on pinned synthetic fixtures and record it separately from actual paint/IME acceptance. Expect unchanged author attributes and byte-exact unaffected source.
- [x] **Step 5: Commit** `git commit -m "feat: apply safe native writing corrections"`.

### Task 12: Connect Living Margin, project controls and production flow

**Files:** Create `WritingDiagnosticsPresentation.swift`, `WritingDiagnosticsSettingsView.swift`, `WritingDiagnosticsPresentationTests.swift`, `WritingDiagnosticsIntegrationTests.swift`; extend `WritingDiagnosticsActions.swift`, `Intelligence/LivingMarginModel.swift`, `Intelligence/LivingMarginView.swift`, `Workspace/WorkspaceShellView.swift`, `SettingsView.swift`, `ContentView.swift` and `Sources/Purlory/PurloryApp.swift` composition. Add final evidence to `docs/engineering/korean-backend-validation.md`.

**Interfaces:** `WritingDiagnosticsPresentation.insights(from: WritingDiagnosticsState) -> [MarginInsight]`. Add producer-scoped `LivingMarginModel.replace(writingQuality: [MarginInsight])` so updates retain future story producers and session dismissals. Extend actions with `perform(_ action: MarginAction, findingID: String) throws`, routing deliberate apply, intentional, disable-rule and learn-word to Tasks 5/11. New project controls consume the repository/controller, not global Settings/User Canon. Add public factories/lifetime methods only where the `Purlory` target needs them.

- [x] **Step 1: Write failing `testPreparedMarginOpenDoesNotAnalyzeOrMoveFocus`, `testDismissIntentionalDisableAndLearnAreDistinct`, `testModelFreeFictionAndGeneralEndToEnd`, `testUnavailableProfileAndBackendRemainWritable`.** Assert:

  ```swift
  XCTAssertEqual(providerCallsFromOpeningMarginOrSettings, 0)
  XCTAssertEqual(firstResponderAfterAutomaticPublication, originalEditor)
  XCTAssertEqual(manuscriptAfterDismissAndProfileActions, originalManuscript)
  XCTAssertEqual(profileWritesAfterDismiss, 0)
  XCTAssertEqual(reopenedProfile, expectedDurableChoices)
  XCTAssertTrue(storyProducerInsightsRemainPresent)
  XCTAssertTrue(editSaveSearchAndExportWorkWhenBackendUnavailable)
  ```

  Use a synthetic project and real provider for the integrated edit→debounce→finding→explicit correction→Undo→flush/reopen path in both modes. Include stale action IDs, current occurrence suppression, learned inflected/name boundaries, profile corruption preservation and engine failure. No shipping LLM or visible Purlory window.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'WritingDiagnosticsPresentationTests|WritingDiagnosticsIntegrationTests|LivingMargin'`; expect disconnected production flow/actions.
- [x] **Step 3: Implement presentation and explicit controls.** Group related style/rhythm findings with original evidence and plain Korean explanations; correctness alternatives are explicit buttons. Keep info patterns in report output unless an actionable grouped margin suggestion exists. Use existing action kinds/custom IDs with a current owned lookup, never parse replacement text from action IDs. Dismiss stays session-only; intentional, disable-rule and learn-word use the versioned project record. Add repetition/dialogue/language controls under Writing settings for the active project, with disabled/no-project and preserved-unreadable states. Compact status/details/retry controls distinguish pending, partial, paused and unavailable without forcing panels/focus or model setup. Accessibility names include category, evidence and action; do not rely on color or native scores. Wire exactly one app-lifetime controller to document commits, project transitions, foreground policy and margin actions. Opening a surface only reads prepared values.
- [x] **Step 4: Run** targeted suites, then full deterministic tests, build, bench compile, native gate verification and clean developer-bundle/unsigned-archive resource validation. Inspect notices/support output for forbidden manuscript/profile content. Expect all existing and new checks passing; do not launch local Purlory or UI scripts. Mandatory cloud CI launch/archive jobs still run unchanged.
- [ ] **Step 5: Commit** `git commit -m "feat: connect Korean proofreading to editor and margin"`. Review inline against the approved spec, publish/attach the bounded PR and merge only when all required CI is green.

## Verification and closeout

For every implementation PR, capture the failing regression result before implementation, the passing targeted result after it, and required build/test/bench/CI evidence. Run Swift commands sequentially with locked resolution. Native tests use a temporary synthetic `CFFIXED_USER_HOME`, leaving the actual home/model cache/manuscripts intact. Do not broaden testing repeatedly after a green run unless changes or failures justify it.

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
swift build --product PurloryBench --disable-automatic-resolution
python3 scripts/test-korean-backend-validation.py
scripts/validate-korean-backend.sh --verify --output build/korean-backend-verification
python3 scripts/test-purlory-notices.py
```

After packaging/integration changes, also build/validate the developer bundle and unsigned archive without running local smoke/UI scripts. Preserve retained bundles before scripts replace `build/Purlory.app`. Record source/tree/artifact identities and frozen-budget results; never describe developer packaging as Store distribution proof.

Required PR jobs remain `Purlory / Debug Build & Test`, `App / Release Bundle & Smoke` and `App / Unsigned Xcode Archive`. Inspect their current conclusions and matching PR head before merge; attach every created PR. Confirm main CI after merge and synchronize local main without overwriting owner changes. Task 1 may require its isolated harness commands in addition to the unchanged main-product jobs.

Keep #126 open while required E2E/native acceptance is pending. Record implementation/CI completion separately from the batched candidate checks under #119: Hangul composition, Ghost keys, correction Undo/Redo, VoiceOver, palette/underline appearance, focus and actual writing feel. The owner will perform app checks later; no new permission/unlock loop is part of this plan. #270 remains open for story/model producers, #114 for Review UI, #269 for contextual local-model answers, and #185 for complete distribution audit. No fabricated grammar completeness, smaller-device support or shipping-model evidence.

## Inline plan review record

The plan maps backend validation to Tasks 1–2; coordinates/incrementality to 3–4; durable decisions to 5; real correctness/style/session rules to 6–8; ownership/health/scheduling to 9; reports/pressure to 10; native safety to 11; margin/settings/production composition to 12. Each Review Focus condition has named tests above. Neighboring interface names and coordinate ownership were checked together. This review is inline and does not replace the owner's pending plan review or claim any tests have already run.
