# #149 MINTBench Review — Prompt-State Reuse

> **Issue:** #149 — Make prompt-state reuse capability-aware for hybrid caches
>
> **Companion to:** `2026-09-10-prompt-state-reuse-design.md`
>
> This review is normative for the #149 implementation plan where it refines the benchmark sections of the main design.

## Verdict

The existing MINTBench is a useful baseline but **is not sufficient by itself to prove #149**.

It already provides three valuable capabilities that should be preserved:

1. normal single-prompt latency/throughput runs;
2. manuscript replay with a true prompt-cache cold reset followed by a repeated warm call;
3. real-model cancellation stress that waits for the internal generation task and then verifies a follow-up generation.

The missing piece is a benchmark mode that preserves one cache across a **sequence of edits** and reports the reconciliation decision for every step.

Do not replace the existing replay benchmark. Historical model-lineup numbers depend on its current semantics.

## Finding 1 — Current replay does not measure append typing

`runReplay` currently does, for each cut:

```text
resetPromptCache()
complete(P)  // cold
complete(P)  // repeated warm
```

This is useful for measuring repeated-prompt prefix reuse, but it is not the #149 trajectory:

```text
complete(P)
complete(P + suffix)
```

The distinction matters because the first completion leaves generated Ghost state in the physical cache today. The second identical prompt therefore exercises generated-tail cleanup / rewind behavior before it can be reused.

A non-trimmable hybrid cache may legitimately fail the existing repeated-warm benchmark even if an exact prompt-boundary state could support forward append reuse.

**Decision:** preserve `runReplay` as the historical quality/repeat-warm benchmark and add a separate cache-trajectory mode.

## Finding 2 — Logical append is not enough; physical state must be exact

The existing `PromptCacheBox` records prompt tokens separately from the actual cache offset. After generation, the token ledger may describe `P` while the physical cache contains:

```text
P + generated Ghost tail
```

For a trimmable attention cache, MINT repairs this by trimming from the physical offset back to the desired LCP.

For a non-trimmable recurrent/hybrid cache, simply changing the policy to say `P -> P+x` is `appendSuffix` is **not sufficient**. The runtime must also prove that the reused physical state actually ends at `P`.

Stable `mlx-swift-lm 3.31.4` provides an important feasibility point: `TokenIterator` performs prompt preparation/prefill during initialization, before the async generation loop consumes subsequent generated tokens, and `KVCache.copy()` is public. This creates a possible prompt-boundary snapshot point, but independence, latency, and memory cost must be measured before production use.

**Decision:** #149 may not claim hybrid append reuse based only on the token ledger. MINTBench must distinguish a logical append candidate from an actually reusable exact prompt state.

If the stable API cannot preserve or recover an exact prompt-boundary state cheaply and safely, #149 should report that blocker and rebuild rather than fake a cache hit.

## Finding 3 — The current replay window is not the editor's 512-grid window

`runReplay` currently computes its context with a direct character window:

```text
contextStart = max(0, cut - contextChars)
context = text[contextStart..<cut]
```

The product editor instead snaps the recent-context start to a 512 UTF-16 grid and corrects to a composed-character boundary. Therefore consecutive replay cuts are not a faithful simulation of the editor's actual cache-locality trajectory.

**Decision:** do not duplicate the 512-grid formula inside MINTBench.

For a real 512-boundary benchmark, either:

- extract the editor's pure recent-context window calculation into a small shared/tested helper that both `BlockTextView` and MINTBench call; or
- leave the product-window boundary proof to a focused unit/E2E test and omit it from MINTBench for #149.

A benchmark that merely reimplements the formula in a second place does not satisfy the gate.

## Finding 4 — Separate correctness proof from performance evidence

MINTBench is a real-model integration tool. It should not become the source of truth for prompt-reuse policy correctness.

Use:

```text
MINTCoreTests
  -> deterministic PromptReusePolicy / state-transition correctness

MINTBench
  -> real model + Metal + tokenizer + cache behavior + latency/memory evidence
```

For real-model cache-path parity, use greedy decoding (`temperature = 0`) so the cold oracle and trajectory path are comparable. `mlx-swift-lm` routes temperature zero to argmax sampling.

Keep the existing replay quality runs at their historical sampling settings so old model-lineup results remain comparable.

## Finding 5 — TTFC alone is not diagnostic enough

Current `Completion.timeToFirstChunk` is a useful user-visible metric because it includes tokenization/reconciliation/prefill before the first visible chunk. Keep it.

For #149, however, also expose a prompt-prefill measurement when stable APIs permit it. `TokenIterator.promptPrefillTime` is available in `mlx-swift-lm 3.31.4`, so this should be evaluated before inventing custom timing.

The existing `GenerateCompletionInfo.promptTokensPerSecond` is not a sufficient replacement because early sentence-boundary cancellation can prevent normal completion info from being emitted.

## Finding 6 — Report tails, not only means

The current replay summary reports mean cold/warm TTFC. #119 explicitly tracks interactive p95 behavior.

For #149 benchmark evidence, report at least:

```text
p50 TTFC
p95 TTFC
mean/median reused-token ratio
strategy counts
miss-reason counts
```

With small fixture counts, keep the raw per-step rows as the primary evidence and treat p95 as descriptive rather than statistically strong.

## Finding 7 — Cancellation stress should become state-aware

The current cancellation stress is valuable: it synchronizes on the internal generation start, cancels the parent task, verifies `CancellationError`, then runs a follow-up completion.

For #149, retain this path and add cache telemetry to the follow-up. "The next generation succeeded" is necessary but not sufficient; the benchmark should also show whether the post-cancel state was reused, rewound, or rebuilt and why.

No stale/generated token may be silently treated as authoritative prompt state.

## Proposed MINTBench extension

Add one dedicated mode, conceptually:

```text
--cache-trajectory
```

Do not overload `--replay` semantics.

A scenario should reset the prompt cache **once at the start**, then execute an ordered trajectory such as:

```text
P0                       baseline
P0                       repeat-warm / generated-tail reconciliation
P0 + a                   strict append candidate
P0 + ab                  repeated append candidate
P0 + a                   backspace
P0 + a with middle edit  divergence
cancel(P1)               in-flight cancellation
P1 + suffix              post-cancel follow-up
```

Use real assembled continuation prompts rather than synthetic cache offsets.

For each step record:

```text
scenario
step
expected relationship to previous prompt
cacheStrategy
cacheMissReason
promptTokens
reusedTokens
prefilledTokens
prefillMs
TTFC
```

If a prompt-boundary snapshot/copy experiment becomes necessary to make hybrid append physically exact, additionally record:

```text
snapshot/copy ms
MLX active memory
MLX peak memory
```

`MLX.Memory` exposes active/cache/peak memory and allows peak reset, so MINTBench can measure this without OS-level RSS heuristics if the target imports MLX directly or MINTCore provides a small benchmark SPI.

## Cold oracle procedure

Do not destroy the warm trajectory state between each step to compute the oracle.

Use two sequential phases with the same loaded model:

### Phase A — fresh oracle

For every scenario prompt:

```text
resetPromptCache()
complete(prompt, temperature: 0)
store output + timing
```

### Phase B — warm trajectory

```text
resetPromptCache() once
complete(P0, temperature: 0)
complete(P1, temperature: 0)
complete(P2, temperature: 0)
...
```

Compare the warm-trajectory output with the corresponding fresh oracle output. The primary correctness assertion is semantic/output parity under greedy decoding; the primary performance evidence is the warm trajectory's reuse/prefill/TTFC telemetry.

The oracle should not be run with a second simultaneously resident model container because that would distort memory measurements on 32GB systems.

## Implementation shape

Do not grow the already large `Sources/MINTBench/main.swift` with all scenario logic.

Prefer:

```text
Sources/MINTBench/main.swift
  -> CLI parsing / dispatch only

Sources/MINTBench/CacheTrajectoryBench.swift
  -> scenario definitions
  -> fresh-oracle pass
  -> warm-trajectory pass
  -> per-step and aggregate reporting
```

Policy decisions and state-transition logic remain in `MINTCore`; MINTBench only drives public/SPI benchmark surfaces and reports evidence.

No new standalone benchmark framework is required.

## #149 benchmark acceptance refinement

For #149 to be considered proven:

- the historical `--replay` mode still produces comparable cold/repeat-warm output;
- `--cache-trajectory` demonstrates the actual edit sequence rather than repeated identical prompts;
- every trajectory step explains `append`, `rewind`, or `rebuild` and the miss reason when applicable;
- a fresh greedy oracle and the supported cached path produce the same completion for deterministic fixtures;
- cancellation follow-up reports state strategy and cannot reuse unproven speculative tail state;
- Basil's current pure-attention reuse/TTFC does not materially regress;
- a supported hybrid model either demonstrates real append-state reuse or records the exact reason the physical prompt boundary cannot be preserved with stable APIs;
- if a prompt-boundary snapshot is introduced, copy time and MLX peak memory are measured before it is accepted;
- 512-boundary evidence uses the actual shared product window calculation or is explicitly delegated to unit/E2E coverage rather than duplicated in the benchmark.

## Consequence for the implementation plan

The implementation plan should start with **telemetry and benchmark shape before changing cache mutation semantics**. Otherwise a faster result could be attributed to the wrong path.

Recommended order:

```text
1. Preserve current MINTBench replay output as baseline
2. Add cache-strategy/miss-reason telemetry to Completion
3. Add deterministic cache-trajectory harness
4. Capture 3.31.3 Basil + hybrid baseline
5. Evaluate/upgrade mlx-swift-lm 3.31.4
6. Re-run identical benchmark matrix
7. Implement pure append/rewind/rebuild policy
8. Re-run trajectory + fresh oracle
9. If hybrid append is still blocked by generated-tail state:
     measure prompt-boundary snapshot feasibility
10. Productionize only the state path supported by correctness + latency + memory evidence
```

This order keeps MINTBench as an instrument rather than changing the instrument and the runtime simultaneously without a trustworthy before/after baseline.
