# Writing candidate benchmark — 2026-10-27

## Scope and outcome

The three owner-requested 4-bit candidates load through MINT's revision-pinned installation store and generate Korean with the native MLX engine. This is experimental hardware evidence on the editorial redesign branch, not approval of a shipping model or completion of the broader core-feature migration/main merge.

The isolated experiment reclaimed **48.93 GiB** by removing six obsolete Hugging Face model caches. Original manuscript/project data was not removed. The three new candidates occupy approximately 27.7 GiB together; the pre-existing Ollama Qwen model was retained. Exact cleanup evidence is in `build/writing-model-benchmarks-2026-10-26/cleanup.json`.

## Reproducibility

- Apple M2 Max, 32 GiB unified memory; reported Metal working set 26,800,603,136 bytes.
- Existing candidate budget: 16,080,361,881 bytes (14.98 GiB), unchanged.
- MLX Swift 0.32.3 (`19601207e9a0de51e03ee6ec0c3c5f3784275075`); MLX Swift LM 3.32.3 (`3b339ad6e3b3f44c8121ecff5131c7fd55e075e6`).
- Optimized `MINTBench`; matching revision-stamped Metal library. Canonical executable path: `.build/arm64-apple-macosx/release/MINTBench`.
- Fixture: `Fixtures/replay-novel-ko-v1.txt`; SHA-256 `563dd6160dd37bea235aadb9cb5fea8ee39a8e6dd4250b6d6cebc38a7d6df841`.
- 12 cuts per style, 1,200-character context window, 32 generated tokens maximum, temperature 0, top-p 0.9, 3,072 prompt-token cap, context mode C, Knowledge off.
- One inference process at a time, no concurrent build during comparison; `CFFIXED_USER_HOME` points into the experiment's `home` directory. No real manuscripts were used.
- Raw logs, schema-2 JSON reports, commands and serial runner are retained under `build/writing-model-benchmarks-2026-10-26/`. Selected results use `*-runtime3323` files; Gemma continuation uses `*-runtime3323-awake`.

Pinned artifacts:

| Model | Hugging Face artifact | Immutable revision |
|---|---|---|
| Qwen3.5 9B | `mlx-community/Qwen3.5-9B-4bit` | `8b2b98c00a6b4d291155e4890773ca8f769aee53` |
| Ministral 3 14B | `mlx-community/Ministral-3-14B-Instruct-2512-4bit` | `95b6f345475c8c8c92b7959d02f4ad86d3ba8384` |
| Gemma 4 26B-A4B | `mlx-community/gemma-4-26b-a4b-it-4bit` | `0d77464eeb233a2da68ebf9d7dc4edaac7db956d` |

## Comparable replay results

TTFC is mean seconds to the first emitted text chunk. “Cold” resets prompt cache; it does not mean a fresh OS filesystem cache. “Repeat” replays the same prompt immediately, and must not be presented as performance for arbitrary edits. Nonempty counts describe displayed cold outputs. Matching proxies compare the generated text to the fixture's held-out continuation: prefix means at least two matching leading characters; eojeol means sharing a whitespace-delimited token of at least two characters. Neither measures human acceptance or full-sentence correctness.

| Model | Style | Nonempty | TTFC cold / repeat (s) | Peak process GiB | Prefix / eojeol proxy |
|---|---|---:|---:|---:|---:|
| Qwen3.5 9B | continuation | 10/12 | 1.460 / 1.457 | 5.96 | 16.7% / 0.0% |
| Qwen3.5 9B | instruct | 12/12 | 1.692 / 1.692 | 5.90 | 0.0% / 16.7% |
| Ministral 3 14B | continuation | 12/12 | 2.486 / 0.058 | 8.01 | 16.7% / 25.0% |
| Ministral 3 14B | instruct | 12/12 | 2.851 / 2.838 | 8.02 | 0.0% / 25.0% |
| Gemma 4 26B-A4B | continuation | 9/12 | 1.166 / 0.957 | 14.62 | 0.0% / 0.0% |
| Gemma 4 26B-A4B | instruct | 12/12 | 1.188 / 1.077 | 14.62 | 0.0% / 33.3% |

All six selected reports completed 12 samples with zero runtime failures. Raw and displayed reasoning-tag, chat-boilerplate and Han-character counters were zero. These counters do **not** establish semantic quality: Gemma continuation includes malformed repetition and irrelevant fragments; Qwen continuation also has two empty displayed outputs.

Ministral continuation reused 99.84% of prompt tokens in the same-prompt replay. Qwen and Gemma reuse was zero under MINT's conservative exact-prefix cache policy. Instruction mode deliberately uses fresh prompt state. The CLI's generic “KV cache not working” warning is therefore not sufficient evidence of a defect.

The initial Gemma continuation report is excluded from latency comparison: an individual 593.80-second wall-clock TTFC was incompatible with the parent's 80.09-second monotonic total. The original remains available as evidence; the selected repeat ran with an idle-sleep inhibitor and showed no such discontinuity. Current wall-clock latency instrumentation still needs care around machine sleep/clock changes.

## Synthetic continuation and native editor

For `도경은 문을 열었다. 방 안에는`:

| Candidate / style | Actual generated text |
|---|---|
| Qwen / continuation | ` 아무도 없었다.` |
| Ministral / continuation | ` 한 남자가 서 있었다.` |
| Gemma / continuation | ` 모를 열다.` — unsuitable in this probe |
| Gemma / instruct | `짙은 어둠과 함께 서늘한 공기가 그를 맞이했다.` |

Gemma should be evaluated as an instruction-style candidate; successful loading and fast generation do not make its raw continuation suitable. The three models' observed peaks fit this short-context experiment's budget, but Gemma leaves only about 0.36 GiB below the cap. This is not evidence of fit at longer contexts, on smaller Macs, or with every background feature active.

All three final opt-in native editor tests passed:

| Model / tested style | Actual visible Ghost | Tab / undo |
|---|---|---|
| Qwen / continuation | ` 아무도 없었다.` | Passed / passed |
| Ministral / continuation | ` 한 남자가 서 있었다.` | Passed / passed |
| Gemma / instruct | `어둠이 짙게 깔려 있었다.` | Passed / passed |

Evidence: `native-results.json`, `qwen-final-native-ghost.log`, `ministral-final-native-ghost.log`, `gemma-final-native-ghost.log` and matching PNG captures in the experiment directory. The native text layer captures use the real manuscript surface behind the transparent text view. The entire SwiftUI host capture from the earlier attempt was invalid and is not used as evidence.
 The tests use the real model, real redesign editor, native insertion and Tab events, then verify both serialized and durable manuscript text after acceptance and undo. Instruction-style native testing uses a completed word followed by a typed space; raw continuation uses the typed Hangul suffix `는`. This difference is explicit and is not used for cross-model latency comparison.

## Implementation and verification

- Added immutable manifests and preset identifiers; shipping `ModelMemoryPolicy.approvedEntries` remains empty.
- Upgraded the inference runtime because [MLX Swift LM 3.32.3](https://github.com/ml-explore/mlx-swift-lm/releases/tag/3.32.3) adds Gemma 4 MoE text support missing from 3.31.3.
- Omitted Ministral's optional stale index, which references four nonexistent shards. Both actual shards retain their original immutable sizes and SHA-256 checks. The strict model loader verifies parameter coverage. The upstream index and original receipt are archived in the experiment directory; installer integrity checks were not weakened.
- Adapted throwing cache creation and rejected-tool events to the new runtime. Added regression coverage for releasing failed cache creation and separating the new cache configuration variants.
- Actual editor testing exposed Ghost acceptance coalescing with the author's last typed character. Tab and right-arrow acceptance now bracket native insertion with undo-coalescing boundaries; deterministic tests failed before the fix and pass after it.
- A focused accessibility test exposed a pre-existing nil `NSApp` read during text view initialization; the current-event lookup now tolerates an uninitialized application.
- Focused inference/cache/installation/memory/accessibility/report suite: 72 passed. Native acceptance undo suite: 2 passed. Optimized MINTBench build and matching Metal preparation passed.
- Full isolated-home suite: **1,466 tests, 4 skipped, 36 failures (3 unexpected)** across the 19 methods below. Main merge is not cleared. These are failures in the current dirty redesign checkout; no clean baseline comparison is claimed. The three final native model checks passed separately, as recorded above.

Failing methods:

- `DocumentOutlineWorkspaceTests.testGeneralOutlinePanelKeepsEditorUndoAndSavedToolSelection`
- `FramedWorkspaceTests.testLongProjectTitleKeepsNavigatorCloseInsideCard`
- `FramedWorkspaceTests.testNavigatorColumnKeepsEditorAllocationAndIdentityAtNarrowWidths`
- `FramedWorkspaceTests.testNavigatorLocalCloseReturnsToEditor`
- `FramedWorkspaceTests.testPocketToolActionsPreserveCompositionAndToggleStoredTools`
- `FramedWorkspaceTests.testRailExposesFunctionalActionsAndSelectedNavigatorState`
- `FramedWorkspaceTests.testRailSearchHonorsMarkedTextAndEditability`
- `FramedWorkspaceTests.testRailToggleAndResizePreserveEditorAndPreferences`
- `FramedWorkspaceTests.testWindowTitleHitTestingReachesNativeDragRegion`
- `LivingMarginWorkspaceTests.testPreparedResultsNeverAutoOpenAndProjectSwitchRetiresExplicitOpening`
- `LivingMarginWorkspaceTests.testRailOpensAndClosesExistingPanelWithoutAnalysisOrEditorReplacement`
- `SerializationTests.testSmartSelectionWrapping`
- `SerializationTests.testSourceModePreservesMarkdown`
- `SerializationTests.testStrikethroughAndHighlightRoundTrip`
- `StoryMapShellTests.testActualFictionMapWorksWithAIOffAndKeepsEditorAcrossJumpReturnAndClose`
- `WorkspaceCommandPaletteTests.testTitleDoesNotSearchAndPouchOpensEmbeddedSearch`
- `WriterCompatibilityTests.testRailExposesAccessibleSearchAndCompatibilityMenuInGeneral`
- `WritingDiagnosticsEditorTests.testCorrectionIsOneUndoableEdit`
- `WritingEditorProjectionTests.testLoadAndNativeEditMapsMatchCanonicalSource`

## Remaining integration scope

This experiment does not choose a release default, approve model licensing/tier coverage, validate long-context quality, or merge main. The next integration pass must audit the existing core features against the redesigned surfaces, verify cursor-bounded retrieval and foreground/background scheduling with the chosen candidate, and finish actual-app Hangul IME, accessibility, recovery/round-trip and required CI evidence. Owner-approved model/tier/license decisions remain governed by #180/#155; the broader merge remains governed by #99.

## Integration follow-up — 2026-10-28

The build, EPUB, editor, and redesigned-control failures listed above are historical results from the experiment. They were resolved and reverified in [the integration pass](redesign-merge-verification-2026-10-28.md). The full local suite now passes; shipping-model/tier/license approval remains separate.
