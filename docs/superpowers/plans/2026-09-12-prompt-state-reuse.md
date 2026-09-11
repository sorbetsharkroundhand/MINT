# Prompt-State Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MINT's continuation runtime explain and safely reuse exact prompt state through explicit append / rewind / rebuild decisions, while preserving the proven Basil path and adding real-editing MINTBench evidence for #149.

**Architecture:** Keep `CompletionEngine` as the single resident-model owner and evolve `PromptCacheBox` rather than introducing a server-style cache subsystem. A pure `PromptReusePolicy` decides from exact token/state facts; `PromptCacheBox` performs the mutation and fails closed. MINTBench gains a separate real-editing cache-trajectory mode while historical identical-prompt replay remains unchanged.

**Tech Stack:** Swift 6, XCTest, Swift Package Manager, MLX, `mlx-swift-lm` stable 3.31.4 evaluation, MINTBench, macOS 14+ Apple Silicon.

**Spec:** `docs/superpowers/specs/2026-09-10-prompt-state-reuse-design.md`

**Benchmark review:** `docs/superpowers/specs/2026-09-10-prompt-state-reuse-mintbench-review.md`

**Release authority:** GitHub #99 (`MINT RELEASE`) supersedes the historical broad 0.2.0 roadmap. #149 is already a required release workstream; #154 owns final usefulness/hardware/budget evidence, #156 owns global README/PLAN/AGENTS synchronization, and #119 owns the final RC gate.

## Global Constraints

- MINT RELEASE remains editor-first, local-only, and must not upload manuscript/prompt telemetry.
- Preserve Hangul IME, cursor-line highlight, Ghost `Tab` / right-arrow / `Esc`, undo, cancellation, and model-lifetime behavior.
- One resident inference engine/model remains the runtime architecture; do not add a second always-resident model for cache management.
- Correctness and fresh-oracle agreement outrank cache hit rate and TTFC.
- Never infer cache safety from model IDs or marketing names.
- Exact prompt-token ledger and exact realized state position must agree before an append-only state is reused.
- If generated Ghost tokens or partial work make the physical state extend past the authoritative prompt and that tail cannot be removed exactly, rebuild.
- Do not pin MINT RELEASE to unreleased `mlx-swift-lm` `main` cache internals.
- Do not add RadixCache, Paged KV, multi-document cache LRU, disk prompt cache, large checkpoint banks, or custom recurrent kernels.
- Historical `--replay` semantics and historical model-lineup numbers remain comparable; do not silently redefine “warm replay.”
- MINTBench cache-trajectory evidence must represent actual append/edit/backspace/cancel trajectories, not two identical prompts.
- Global release-scope documentation (`README.md`, root `PLAN.md`, `AGENTS.md`) is owned by #156; #149 may update only inference/benchmark documentation that would otherwise be factually wrong.
- Every production slice runs `swift test`, `swift build`, and `swift build --product MINTBench`; real-model benchmark evidence is recorded separately from deterministic unit tests.

---

## File Structure

The implementation should keep responsibilities narrow:

- `Sources/MINTCore/Inference/PromptReusePolicy.swift` — **new** pure decision types and logic; no MLX imports.
- `Sources/MINTCore/Inference/PromptCache.swift` — mutable MLX cache ownership and safe application of a `PromptReuseDecision`.
- `Sources/MINTCore/Inference/CompletionEngine.swift` — exposes per-completion cache telemetry and reliable prompt-prefill timing; keeps model/generation lifecycle unchanged.
- `Sources/MINTCore/Inference/RecentContextWindow.swift` — **new** pure shared 512-UTF16 context-window calculation so editor and benchmark use one implementation.
- `Sources/MINTCore/Editor/BlockTextView.swift` — delegates recent-window slicing to `RecentContextWindow`; no behavior change intended.
- `Sources/MINTBench/CacheTrajectoryBench.swift` — **new** real-editing cache trajectory runner and fresh-oracle comparison.
- `Sources/MINTBench/main.swift` — CLI parsing/dispatch and unchanged legacy replay.
- `Tests/MINTCoreTests/PromptReusePolicyTests.swift` — **new** pure policy table.
- `Tests/MINTCoreTests/PromptCacheMathTests.swift` — retain/adjust only legacy LCP/trim arithmetic that remains relevant.
- `Tests/MINTCoreTests/RecentContextWindowTests.swift` — **new** exact 512-grid/shared-window tests.
- `Package.swift`, `Package.resolved` — stable dependency evaluation/update.
- `docs/model-lineup-bench.md` — correct the old “hybrid reuse structurally impossible” statement after implementation evidence.
- `docs/m6-knowledge.md` — make historical prewarm claims truthful if source still lacks the documented path.
- `docs/prompt-state-reuse-evidence.md` — **new** command lines, environment, before/after benchmark table, blockers, and final #149 decision evidence.

The implementation does **not** modify root `PLAN.md`, `README.md`, or `AGENTS.md`; #156 owns that release-scope synchronization.

---

### Task 1: Freeze Current Behavior and Evaluate `mlx-swift-lm 3.31.4`

**Files:**
- Modify: `Package.swift`
- Modify: `Package.resolved`
- Create: `docs/prompt-state-reuse-evidence.md`
- Inspect: `Sources/MINTCore/Inference/CompletionEngine.swift`
- Inspect: `Sources/MINTCore/Inference/PromptCache.swift`
- Inspect: `Sources/MINTBench/main.swift`

**Interfaces:**
- Consumes: current `CompletionEngine.complete`, `resetPromptCache`, historical `MINTBench --replay`.
- Produces: a locked dependency decision and baseline evidence used by every later task.

- [ ] **Step 1: Record the pre-upgrade dependency and benchmark contract**

Create `docs/prompt-state-reuse-evidence.md` with this exact opening structure:

```markdown
# Prompt-State Reuse Evidence — #149

## Environment
- Hardware: Mac model / RAM recorded at run time
- OS: recorded at run time
- Build: `swift build -c release`
- Branch: `149-prompt-state-reuse`

## Benchmark semantics
- Legacy replay: `P -> P`; measures same-prompt recovery/reuse after Ghost decode.
- Cache trajectory: `P -> P+x -> edit/backspace/cancel`; added by #149.
- Do not interpret legacy replay as append-only hybrid reuse evidence.

## Dependency baseline
| Item | Before | Candidate |
| --- | --- | --- |
| mlx-swift-lm | 3.31.3 resolved | 3.31.4 stable |
| mlx-swift | 0.31.4 | unchanged unless resolver requires otherwise |
```

- [ ] **Step 2: Run deterministic baseline before touching the dependency**

Run:

```bash
swift test
swift build
swift build --product MINTBench
```

Expected: all commands PASS on the branch before dependency update. Record failures verbatim if the branch is not green; do not attribute pre-existing failures to 3.31.4.

- [ ] **Step 3: Capture current real-model baseline when the model is locally available**

Run at least Basil with the existing historical command:

```bash
swift run -c release MINTBench \
  --model mlx-community/GLM-4.7-Flash-4bit \
  --replay Fixtures/replay-novel-ko-v1.txt \
  --context 1200 \
  --style continuation
```

Record cold TTFC, warm TTFC, prompt tokens, warm reused tokens, and any failure. Do not block deterministic code work if weights are unavailable; record the exact model/download blocker.

- [ ] **Step 4: Update the stable dependency only**

Change `Package.swift` to:

```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
```

Then run:

```bash
swift package update mlx-swift-lm
```

Verify `Package.resolved` selects stable `3.31.4`, not a branch/main revision.

- [ ] **Step 5: Re-run deterministic verification**

Run:

```bash
swift test
swift build
swift build --product MINTBench
```

Expected: PASS with no new MINT-owned warnings.

- [ ] **Step 6: Re-run the same Basil baseline**

Use exactly the Step 3 command and append a before/after table to the evidence doc. Acceptance for this task: no correctness/model-load regression and no material Basil warm-path regression attributable to the dependency. If a regression exists, revert the version change but keep the evidence explaining why #149 remains on 3.31.3.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Package.resolved docs/prompt-state-reuse-evidence.md
git commit -m "chore(inference): evaluate mlx-swift-lm 3.31.4"
```

---

### Task 2: Extract a Pure Prompt Reuse Policy with Physical-State Exactness

**Files:**
- Create: `Sources/MINTCore/Inference/PromptReusePolicy.swift`
- Create: `Tests/MINTCoreTests/PromptReusePolicyTests.swift`
- Modify: `Tests/MINTCoreTests/PromptCacheMathTests.swift`

**Interfaces:**
- Consumes: exact `representedTokens`, exact `requestedTokens`, current realized state position, model identity match, and rewind capability.
- Produces:

```swift
enum PromptReuseStrategy: String, Sendable, Equatable {
    case append
    case rewind
    case rebuild
}

enum PromptReuseMissReason: String, Sendable, Equatable {
    case none
    case emptyPrompt
    case modelMismatch
    case noRepresentedPrompt
    case stateBeforeRepresentedPrompt
    case speculativeTailRequiresRewind
    case zeroCommonPrefix
    case nonRewindableDivergence
    case incompleteRewind
    case unknownState
}

struct PromptReuseDecision: Sendable, Equatable {
    let strategy: PromptReuseStrategy
    let reusedTokens: Int
    let suffixStart: Int
    let trimTokens: Int
    let reason: PromptReuseMissReason
}

enum PromptReusePolicy {
    static func decide(
        representedTokens: [Int],
        requestedTokens: [Int],
        realizedTokenCount: Int?,
        modelMatches: Bool,
        canRewindExactly: Bool
    ) -> PromptReuseDecision
}
```

- [ ] **Step 1: Write failing strict-append tests**

Add tests equivalent to:

```swift
func test_strictAppend_whenStateEndsAtPrompt_usesAppendWithoutTrim() {
    let decision = PromptReusePolicy.decide(
        representedTokens: [1, 2, 3],
        requestedTokens: [1, 2, 3, 4, 5],
        realizedTokenCount: 3,
        modelMatches: true,
        canRewindExactly: false)

    XCTAssertEqual(decision.strategy, .append)
    XCTAssertEqual(decision.reusedTokens, 3)
    XCTAssertEqual(decision.suffixStart, 3)
    XCTAssertEqual(decision.trimTokens, 0)
    XCTAssertEqual(decision.reason, .none)
}

func test_strictAppend_withGeneratedTailAndNoRewind_rebuilds() {
    let decision = PromptReusePolicy.decide(
        representedTokens: [1, 2, 3],
        requestedTokens: [1, 2, 3, 4],
        realizedTokenCount: 7,
        modelMatches: true,
        canRewindExactly: false)

    XCTAssertEqual(decision.strategy, .rebuild)
    XCTAssertEqual(decision.reason, .speculativeTailRequiresRewind)
}
```

- [ ] **Step 2: Write failing rewind/rebuild table tests**

Cover all of these exact cases:

```text
same prompt, realized == represented        -> rewind one input token if exact rewind is supported; otherwise rebuild
strict append, realized == represented      -> append
strict append, realized > represented       -> rewind tail then reuse only if rewind is exact; otherwise rebuild
divergence with LCP > 0 + rewindable        -> rewind
divergence with LCP > 0 + non-rewindable    -> rebuild / nonRewindableDivergence
LCP == 0                                    -> rebuild / zeroCommonPrefix
realized < represented.count                -> rebuild / stateBeforeRepresentedPrompt
model mismatch                              -> rebuild / modelMismatch
nil/unknown realized position               -> rebuild / unknownState
empty requested prompt                      -> rebuild / emptyPrompt
```

- [ ] **Step 3: Run the new tests and verify RED**

Run:

```bash
swift test --filter PromptReusePolicyTests
```

Expected: compile/test failure because the policy file/types do not exist yet.

- [ ] **Step 4: Implement the minimal pure policy**

Use a private LCP helper and enforce this ordering:

```swift
if !modelMatches { rebuild(.modelMismatch) }
if requestedTokens.isEmpty { rebuild(.emptyPrompt) }
guard let realizedTokenCount else { rebuild(.unknownState) }
guard !representedTokens.isEmpty else { rebuild(.noRepresentedPrompt) }
guard realizedTokenCount >= representedTokens.count else {
    rebuild(.stateBeforeRepresentedPrompt)
}

if requestedTokens.starts(with: representedTokens) {
    if realizedTokenCount == representedTokens.count {
        return append(reused: representedTokens.count)
    }
    guard canRewindExactly else {
        return rebuild(.speculativeTailRequiresRewind)
    }
    return rewind(
        reused: representedTokens.count,
        trim: realizedTokenCount - representedTokens.count,
        suffixStart: representedTokens.count)
}

let lcp = longestCommonPrefix(representedTokens, requestedTokens)
guard lcp > 0 else { return rebuild(.zeroCommonPrefix) }
guard canRewindExactly else { return rebuild(.nonRewindableDivergence) }
return rewind(reused: adjustedReusablePrefix, trim: realizedTokenCount - adjustedReusablePrefix, suffixStart: adjustedReusablePrefix)
```

For an identical prompt, preserve the existing non-empty-input rule by choosing `requested.count - 1` as the reusable prefix when exact rewind is available. Do not fabricate an append with an empty suffix.

- [ ] **Step 5: Run policy and legacy math tests**

Run:

```bash
swift test --filter PromptReusePolicyTests
swift test --filter PromptCacheMathTests
```

Expected: PASS. Keep `PromptCacheMath` only for arithmetic that `PromptCacheBox` still uses; delete duplicated decision logic after Task 3, not before.

- [ ] **Step 6: Commit**

```bash
git add Sources/MINTCore/Inference/PromptReusePolicy.swift \
  Tests/MINTCoreTests/PromptReusePolicyTests.swift \
  Tests/MINTCoreTests/PromptCacheMathTests.swift
git commit -m "feat(inference): add exact prompt reuse policy"
```

---

### Task 3: Apply the Policy in `PromptCacheBox` and Emit Explainable Telemetry

**Files:**
- Modify: `Sources/MINTCore/Inference/PromptCache.swift`
- Modify: `Sources/MINTCore/Inference/CompletionEngine.swift`
- Test: `Tests/MINTCoreTests/PromptReusePolicyTests.swift`
- Test: existing cache/cancellation tests under `Tests/MINTCoreTests/`

**Interfaces:**
- Consumes: `PromptReusePolicy.decide(...)` from Task 2.
- Produces:

```swift
public struct PromptReuseTelemetry: Sendable, Equatable {
    public let strategy: PromptReuseStrategy
    public let missReason: PromptReuseMissReason
    public let promptTokens: Int
    public let reusedTokens: Int
    public let prefilledTokens: Int
    public let prefillMilliseconds: Double?
}
```

`CompletionEngine.Completion` gains:

```swift
public let promptReuse: PromptReuseTelemetry
```

- [ ] **Step 1: Add failing tests for state-application invariants**

Add deterministic tests around policy-to-mutation bookkeeping where possible without a model:

```swift
func test_generatedTail_isNotClassifiedAsTrimFreeAppend() { ... }
func test_nonRewindableDivergence_reportsRebuildReason() { ... }
func test_modelMismatch_reportsRebuildBeforeMutation() { ... }
```

If `KVCache` cannot be faked cleanly, keep mutation-specific assertions at the pure policy boundary and add a small internal bookkeeping helper rather than introducing a fake MLX model hierarchy.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --filter PromptReusePolicyTests
```

Expected: FAIL for the newly referenced telemetry/bookkeeping API.

- [ ] **Step 3: Change `PromptCacheBox.Reuse` to carry decision evidence**

Use a shape equivalent to:

```swift
struct Reuse {
    let cache: [KVCache]
    let suffix: [Int]
    let decision: PromptReuseDecision
}
```

`begin(...)` must:

1. read a trustworthy realized position only when the current cache topology exposes one consistently;
2. call the pure policy before mutation;
3. `.append` only when physical state is already exactly at the authoritative prompt boundary;
4. `.rewind` by `decision.trimTokens`, require `trimPromptCache(...) == decision.trimTokens`, otherwise discard and build fresh;
5. `.rebuild` by replacing the cache with `makePromptCache(...)` and returning the full requested tokens;
6. never publish a partial trim as reuse.

- [ ] **Step 4: Preserve the current Basil generated-tail path**

For pure-attention/trimmable state after Ghost decode, a new strict append will normally need to remove the generated tail before applying the user's suffix. That is a `.rewind` strategy, not a trim-free `.append`. This preserves current correctness/performance and keeps telemetry semantically honest.

- [ ] **Step 5: Add telemetry to `CompletionEngine.Completion`**

For continuation:

```swift
let decision = reuse.decision
let telemetry = PromptReuseTelemetry(
    strategy: decision.strategy,
    missReason: decision.reason,
    promptTokens: promptTokenCount,
    reusedTokens: decision.reusedTokens,
    prefilledTokens: max(0, promptTokenCount - decision.reusedTokens),
    prefillMilliseconds: measuredPrefillMs)
```

For instruct/no-cache paths use `.rebuild` with an explicit reason appropriate to the implementation rather than pretending reuse was attempted. If an additional reason enum case is needed (for example `.cacheDisabled` or `.unsupportedPromptStyle`), add it in Task 2's enum and tests in the same commit.

- [ ] **Step 6: Capture reliable prefill timing only if stable 3.31.4 exposes it**

Prefer upstream `TokenIterator.promptPrefillTime` if accessible from MINT's generation wrapper without changing generation semantics. If `generateTask` hides it and exposing it would require copying/reimplementing upstream generation internals, leave `prefillMilliseconds = nil` and record that limitation in `docs/prompt-state-reuse-evidence.md`.

Do not approximate prefill as `TTFC`.

- [ ] **Step 7: Run deterministic verification**

```bash
swift test
swift build
swift build --product MINTBench
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/MINTCore/Inference/PromptCache.swift \
  Sources/MINTCore/Inference/CompletionEngine.swift \
  Sources/MINTCore/Inference/PromptReusePolicy.swift \
  Tests/MINTCoreTests
git commit -m "feat(inference): apply capability-aware prompt reuse"
```

---

### Task 4: Share the Real 512-UTF16 Recent-Context Window with MINTBench

**Files:**
- Create: `Sources/MINTCore/Inference/RecentContextWindow.swift`
- Modify: `Sources/MINTCore/Editor/BlockTextView.swift`
- Create: `Tests/MINTCoreTests/RecentContextWindowTests.swift`

**Interfaces:**
- Produces:

```swift
struct RecentContextSlice: Sendable, Equatable {
    let text: String
    let startUTF16: Int
}

enum RecentContextWindow {
    static func slice(
        storage: NSString,
        before caretUTF16: Int,
        limit: Int
    ) -> RecentContextSlice
}
```

- [ ] **Step 1: Write failing parity tests from current editor behavior**

Cover:

```swift
func test_shortTextStartsAtZero()
func test_longTextSnapsStartDownTo512Grid()
func test_typingWithinSameGridKeepsStartStable()
func test_crossingGridBoundaryMovesStartBy512()
func test_surrogatePairBoundaryMovesToComposedCharacterBoundary()
func test_returnedStartMatchesReturnedSubstring()
```

Use an emoji or composed Hangul fixture around the computed grid boundary to prove no invalid UTF-16 split occurs.

- [ ] **Step 2: Verify RED**

```bash
swift test --filter RecentContextWindowTests
```

Expected: FAIL because the shared helper does not exist.

- [ ] **Step 3: Move the existing `BlockTextView` algorithm without changing semantics**

The helper must preserve the existing algorithm:

```swift
let raw = max(0, caretUTF16 - limit)
if raw == 0 { return start 0 through caret }
var start = (raw / 512) * 512
start = storage.rangeOfComposedCharacterSequence(at: start).location
return substring(start..<caretUTF16)
```

Clamp caret/start safely to the storage bounds exactly once in the helper.

- [ ] **Step 4: Replace `BlockTextView`'s private slicing body with the helper**

The editor remains the behavior authority; this task is a refactor for parity, not a context-algorithm change.

- [ ] **Step 5: Run tests/build**

```bash
swift test --filter RecentContextWindowTests
swift test
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/MINTCore/Inference/RecentContextWindow.swift \
  Sources/MINTCore/Editor/BlockTextView.swift \
  Tests/MINTCoreTests/RecentContextWindowTests.swift
git commit -m "refactor(editor): share stable recent context window"
```

---

### Task 5: Add a Separate Real-Editing `MINTBench --cache-trajectory` Mode

**Files:**
- Create: `Sources/MINTBench/CacheTrajectoryBench.swift`
- Modify: `Sources/MINTBench/main.swift`
- Modify: `docs/prompt-state-reuse-evidence.md`

**Interfaces:**
- Consumes: `CompletionEngine.Completion.promptReuse`, `RecentContextWindow.slice`, existing `CompletionEngine.resetPromptCache()`.
- Produces CLI:

```bash
swift run -c release MINTBench \
  --cache-trajectory Fixtures/replay-novel-ko-v1.txt \
  --model <hf-id> \
  --context 1200
```

Legacy `--replay` keeps its existing behavior and output meaning.

- [ ] **Step 1: Add CLI parsing without changing replay dispatch**

Extend `BenchOptions` with:

```swift
var cacheTrajectoryPath: String?
```

Parse:

```text
--cache-trajectory <file>
```

Dispatch `cacheTrajectoryPath` before `replayPath`; reject simultaneous `--cache-trajectory` and `--replay` with exit code 2 and a clear message.

- [ ] **Step 2: Add explicit trajectory data types in the new file**

Use:

```swift
struct CacheTrajectoryStep {
    enum Kind: String {
        case cold
        case samePrompt
        case append
        case repeatedAppend
        case backspace
        case middleEdit
        case boundaryCross
    }
    let name: String
    let kind: Kind
    let prompt: String
}

struct CacheTrajectoryRow {
    let step: CacheTrajectoryStep
    let oracleText: String
    let warmText: String
    let telemetry: PromptReuseTelemetry
    let ttfc: TimeInterval?
    let oracleMatched: Bool
}
```

- [ ] **Step 3: Build prompts from one deterministic manuscript position**

The sequence must intentionally be stateful:

```text
P0                    cold
P0                    samePrompt
P0 + " 그"            append
P0 + " 그리고"        repeatedAppend
P0 + " 그"            backspace
middle edit of tail   middleEdit
next real 512 window  boundaryCross
```

Use `RecentContextWindow.slice` for `P0` and boundary-cross prompts so the benchmark exercises the same 512-UTF16 window behavior as the editor. Do not duplicate `(raw / 512) * 512` in MINTBench.

- [ ] **Step 4: Build a cold oracle before the warm trajectory**

For each step prompt:

1. `await engine.resetPromptCache()`;
2. run with `temperature = 0` and the same model/settings;
3. store the post-processed output as the fresh oracle.

After all oracle runs, reset once and execute the warm trajectory without resets between steps.

This makes trajectory state causal while keeping correctness comparison deterministic under greedy sampling.

- [ ] **Step 5: Print one evidence row per step**

Format each row with at least:

```text
step=<name>
kind=<kind>
strategy=<append|rewind|rebuild>
reason=<reason>
prompt=<n>tok
reused=<n>tok
prefilled=<n>tok
prefill=<ms|n/a>
TTFC=<ms>
oracle=<match|DIFF>
```

Exit non-zero if a deterministic oracle mismatch occurs on a path MINT claims is safely reusable.

- [ ] **Step 6: Keep legacy replay labeled correctly**

Update the replay header/comment/output to say:

```text
legacy same-prompt warm replay (P -> P)
```

Do not change its reset/two-run behavior or historical aggregate calculation.

- [ ] **Step 7: Build the benchmark executable**

```bash
swift build --product MINTBench
```

Expected: PASS.

- [ ] **Step 8: Run at least one locally available pure-attention/trimmable baseline**

Preferred:

```bash
swift run -c release MINTBench \
  --cache-trajectory Fixtures/replay-novel-ko-v1.txt \
  --model mlx-community/GLM-4.7-Flash-4bit \
  --context 1200 \
  --style continuation
```

Record the full command and summary in `docs/prompt-state-reuse-evidence.md`.

- [ ] **Step 9: Commit**

```bash
git add Sources/MINTBench/main.swift \
  Sources/MINTBench/CacheTrajectoryBench.swift \
  docs/prompt-state-reuse-evidence.md
git commit -m "feat(bench): add real editing cache trajectories"
```

---

### Task 6: Integrate Cancellation and Hybrid Evidence Without Hiding Generated-Tail Limits

**Files:**
- Modify: `Sources/MINTBench/main.swift`
- Modify: `Sources/MINTBench/CacheTrajectoryBench.swift`
- Modify: `docs/prompt-state-reuse-evidence.md`
- Modify tests only if a deterministic lifecycle helper is needed.

**Interfaces:**
- Consumes: existing `completeForCancellationStress`, Task 5 trajectory telemetry.
- Produces: evidence that cancellation leaves the next request either safely reusable or explicitly rebuilt, plus one supported hybrid-model result/blocker.

- [ ] **Step 1: Extend cancellation stress output with the next reuse decision**

After each cancelled generation, the existing follow-up completion already runs. Print/assert its:

```swift
followup.promptReuse.strategy
followup.promptReuse.missReason
followup.promptReuse.reusedTokens
followup.promptReuse.prefilledTokens
```

The test condition is **not** “must reuse.” The condition is that the engine succeeds and the decision is explainable/safe.

- [ ] **Step 2: Add generated-tail evidence to the trajectory report**

When a requested prompt is a strict token extension of `representedTokens` but the realized cache still extends past the prompt because Ghost decode mutated it:

- pure-attention/trimmable cache may report `.rewind` to remove the tail, then prefill the user suffix;
- non-rewindable hybrid cache must report `.rebuild` with `.speculativeTailRequiresRewind` unless a stable prompt-boundary state exists.

Do not relabel that rebuild as an append hit.

- [ ] **Step 3: Run a representative supported hybrid model**

Use the locally supported hybrid candidate from the current model set (for example the existing Peppermint/Qwen hybrid if 3.31.4 loads it):

```bash
swift run -c release MINTBench \
  --cache-trajectory Fixtures/replay-novel-ko-v1.txt \
  --model mlx-community/Qwen3.6-35B-A3B-4bit \
  --context 1200 \
  --style continuation
```

If the model ID/version is unsupported or unavailable, record the exact load/dependency blocker and use another hybrid model supported by the stable dependency. Do not modify production logic by model name just to make the benchmark pass.

- [ ] **Step 4: Decide whether #149 needs a prompt-boundary snapshot follow-up**

Use the evidence table:

```text
If hybrid append is blocked only because generated Ghost tail is non-rewindable:
  record "prompt-boundary state ownership required".

If stable 3.31.4 exposes a bounded, independently testable copy/snapshot path:
  measure it as a spike only; do not productionize in #149 unless the issue is re-reviewed.

If copy/snapshot is not exposed or is too expensive/unproven:
  keep safe rebuild and open/link a follow-up.
```

This task may satisfy #149's hybrid acceptance with a precise blocker; correctness is more important than forcing a reuse percentage.

- [ ] **Step 5: If a copy-cost spike is feasible, measure MLX memory correctly**

Use MLX `Memory.snapshot()` / resettable `peakMemory`, not process RSS, and record:

```text
copy/snapshot ms
active-memory delta
peak-memory delta
fresh-prefill TTFC
```

Keep experimental code out of production files if it is not selected.

- [ ] **Step 6: Run verification**

```bash
swift test
swift build
swift build --product MINTBench
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/MINTBench docs/prompt-state-reuse-evidence.md Tests/MINTCoreTests
git commit -m "test(inference): prove cancellation and hybrid cache trajectories"
```

---

### Task 7: Correct Historical Cache/Prewarm Documentation

**Files:**
- Modify: `docs/model-lineup-bench.md`
- Modify: `docs/m6-knowledge.md`
- Modify: `docs/prompt-state-reuse-evidence.md`
- Do **not** modify: `README.md`, root `PLAN.md`, `AGENTS.md` (#156 ownership)

**Interfaces:**
- Consumes: final Task 5/6 evidence.
- Produces: truthful historical technical documentation without changing current release authority.

- [ ] **Step 1: Replace the over-broad hybrid-cache conclusion**

Change the old statement equivalent to:

```text
KV reuse is only possible on pure-attention models; hybrid reuse is structurally impossible.
```

To evidence-backed wording equivalent to:

```text
The historical MINT LCP-rewind implementation could not reuse a non-trimmable recurrent/hybrid cache after state divergence. Hybrid state is not categorically unreusable: exact append-only reuse is possible only when the realized state is exactly at the authoritative prompt boundary. In the current Ghost architecture, generated decode tail may make that condition false; #149 measures and reports that distinction explicitly.
```

Preserve historical benchmark numbers and dates.

- [ ] **Step 2: Audit `docs/m6-knowledge.md` prewarm claims against source**

Search current source for:

```bash
git grep -n "prewarmPrefix\|CompletionEngine.prewarm\|onPassDidComplete"
```

If the described A+B prewarm path is absent, mark the section as historical/removed and state that current source does not implement it. Do not restore it in #149 unless restoration is trivially compatible with the exact-state contract and independently reviewed.

- [ ] **Step 3: Add final decision summary to evidence doc**

Record:

```text
Dependency: adopted/rejected 3.31.4 + reason
Basil regression: pass/fail + measured values
Hybrid append: proven / blocked by generated tail / unsupported dependency
Cancellation: pass/fail
Oracle mismatches: count
Follow-up required: yes/no + exact reason
```

- [ ] **Step 4: Commit**

```bash
git add docs/model-lineup-bench.md docs/m6-knowledge.md docs/prompt-state-reuse-evidence.md
git commit -m "docs(inference): correct prompt cache and prewarm claims"
```

---

### Task 8: Final #149 Verification and Release-Evidence Handoff

**Files:**
- Inspect all changed files.
- Update: `docs/prompt-state-reuse-evidence.md`
- GitHub metadata/comments only; no global release-plan rewrite in this task.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: reviewable #149 evidence for #154 and #119.

- [ ] **Step 1: Run the full deterministic gate**

```bash
swift test
swift build
swift build --product MINTBench
```

Expected: PASS.

- [ ] **Step 2: Run legacy and trajectory benchmarks on the same selected model(s)**

At minimum preserve one Basil historical comparison and one supported hybrid result/blocker. Put exact commands and output summaries in the evidence doc.

- [ ] **Step 3: Report latency distributions, not only means**

For trajectory TTFC samples report at least count, p50, and p95. Do not invent a pass/fail budget in #149; #154 freezes release numeric budgets. #149 supplies measurement definitions and raw evidence.

- [ ] **Step 4: Review the fresh-oracle invariant**

Any deterministic oracle mismatch on a claimed reuse path is a blocker. Change that path to rebuild before considering #149 complete.

- [ ] **Step 5: Review diff scope**

```bash
git diff --stat main...HEAD
git diff main...HEAD -- Package.swift Package.resolved Sources/MINTCore/Inference Sources/MINTBench Tests/MINTCoreTests docs
```

Verify there is no unrelated Story Intelligence, UI redesign, model picker, or release-distribution work.

- [ ] **Step 6: Hand evidence to the current release graph**

Post a concise #149 comment that includes:

```text
- dependency result
- policy result
- legacy replay result
- real-editing trajectory result
- hybrid result/blocker
- cancellation result
- oracle correctness result
- p50/p95 measurement definition
- follow-up issue if prompt-boundary snapshot is required
```

Reference #154 for final quality/hardware budget evaluation and #119 for RC consumption. Do not close #154/#119 from this branch.

- [ ] **Step 7: Final commit if evidence changed after the last benchmark**

```bash
git add docs/prompt-state-reuse-evidence.md
git commit -m "docs(inference): record final #149 evidence"
```

---

## MINT RELEASE Impact Assessment

This plan **does affect the current first-release plan**, but the effect is already represented in the authoritative GitHub release graph rather than requiring a new release expansion:

1. **#149 is already required by #99.** The current release epic lists `#108 #112 #149` under “Useful local assistance” and explicitly sequences `#149 instruments then validates prompt-state reuse` before #154/#119 evidence.
2. **#149 does not restore deferred #115.** The current #99 explicitly defers #107/#109/#110/#113/#114/#115/#126 to #158. This implementation must not turn Story Context or advanced Fiction Intelligence back into a release dependency.
3. **#154 consumes #149, not vice versa.** #149 owns cache-policy correctness and trajectory instrumentation; #154 freezes numeric budgets, supported hardware tiers, Ghost utility/acceptance, and writer evidence.
4. **#119 remains the final RC gate.** #149 supplies cache correctness/latency evidence but does not define the release candidate by itself.
5. **#156 owns global documentation synchronization.** Root `PLAN.md`, `README.md`, and `AGENTS.md` currently describe historical broad 0.2.0 scope and are intentionally left unchanged here so #149 does not conflict with the focused release-scope documentation PR promised by #156.
6. **Schedule risk is bounded.** The required production slice is policy + telemetry + benchmark trajectory + safe fallback. Prompt-boundary copying/checkpointing is not forced into this release if stable APIs or measured memory/latency do not justify it; a precise blocker is an acceptable #149 result.

### Release dependency shape

```text
#149 Prompt-state correctness + trajectory instrumentation
          │
          ├──────────────→ #154 quality / latency / hardware budgets
          │
          └──────────────→ #119 final RC evidence

#108 source retrieval ─→ #112 minimal Ask/source inspection ─┐
#118 project/runtime handoff ────────────────────────────────┼─→ integrated release evidence
#152 model installation/recovery ────────────────────────────┘

#115 Story Context / advanced intelligence ─→ #158 future, NOT restored by #149
```

Therefore no new release workstream or dependency cycle should be added. The implementation changes the **quality of the evidence and runtime safety inside an already-required release slice**, not the top-level product scope.

---

## Self-Review

### Spec coverage

- Stable 3.31.4 evaluation: Task 1.
- Explicit append / rewind / rebuild policy: Tasks 2–3.
- Generated-tail / authoritative-state exactness: Tasks 2, 3, 6.
- No model-name cache hacks: Global Constraints + Task 2.
- Basil regression protection: Tasks 1, 3, 8.
- Strategy / miss reason / token telemetry: Task 3.
- Real editing trajectories: Task 5.
- Cancellation trajectory: Task 6.
- Real 512-window parity: Task 4 + Task 5.
- Fresh oracle correctness: Task 5 + Task 8.
- Hybrid proof or precise blocker: Task 6.
- Historical prewarm/document truthfulness: Task 7.
- #154/#119 release evidence handoff: Task 8.
- Server-scale cache non-goals: Global Constraints.

### Type consistency

- `PromptReusePolicy` produces `PromptReuseDecision`.
- `PromptCacheBox.Reuse` carries that decision.
- `CompletionEngine.Completion` exposes `PromptReuseTelemetry` derived from the decision.
- `CacheTrajectoryBench` consumes `PromptReuseTelemetry` only; it does not inspect or mutate MLX cache internals.
- `RecentContextWindow` is the single 512-UTF16 slicing implementation shared by editor and benchmark.

### Scope check

The plan intentionally does not productionize canonical/decode cache forks or recurrent checkpoints. If Task 6 proves generated-tail ownership is the only blocker for a valuable hybrid model, that becomes a separately reviewed benchmark-backed follow-up rather than silently expanding #149.