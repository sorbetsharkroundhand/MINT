# Prompt-State Reuse Architecture — Design Specification

> **Issue:** #149 — Make prompt-state reuse capability-aware for hybrid caches
>
> **Milestone:** MINT 0.2.0
>
> **Parent contract:** `docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md`

## Goal

Evolve MINT's Ghost Completion cache layer from a single LCP-and-trim optimization into a small, capability-aware **prompt-state reuse architecture**.

The runtime must preserve the existing pure-attention warm path while allowing hybrid/recurrent models to reuse exact append-only prompt state without requiring arbitrary rewind. The design must remain local, deterministic, fail-closed, and small enough for the 0.2.0 release.

The product-level reason is simple: model selection should be driven primarily by writing quality, not by whether a model's cache topology happens to fit the current `PromptCacheBox` implementation.

## Current State

MINT currently has a strong continuation-specific cache path:

- `ContextAssembler` keeps stable project/context information before recent manuscript text.
- The editor keeps the recent-text window start stable on a 512 UTF-16 grid to preserve prompt locality while typing.
- `PromptCacheBox` stores one live `[KVCache]`, the most recently committed prompt-token ledger, and model identity.
- A new continuation computes the longest common prefix against the recorded prompt.
- Reuse is accepted only when `canTrimPromptCache(cache)` is true.
- The live cache is trimmed from its actual offset back to the LCP, which also removes generated or cancelled tail state.
- Only the requested suffix is then prefilled.
- Any unsafe state falls back to a fresh cache.

This is an effective design for trimmable pure-attention caches and must remain the fast path for models such as the current Basil baseline.

## Problem

The current implementation conflates **forward extension** with **backward reconciliation**.

Given:

```text
cached:    ABC
requested: ABCDEF
```

MINT currently still requires the entire cache to be trimmable, even though no backward operation is needed. A recurrent or hybrid state can often advance from the exact represented prefix to `ABCDEF`; it simply cannot recover an arbitrary earlier state such as `AB` after later state has been committed.

Therefore the current statement "hybrid/recurrent caches cannot be reused" is too broad. The accurate statement is:

> MINT's current arbitrary-LCP-rewind path cannot reuse a non-trimmable recurrent cache after divergence, but exact append-only continuation can be reused without rewind.

This distinction is especially important for modern Gated Delta / Mamba-style hybrid models.

## Ecosystem Findings

The design is informed by current inference-engine practice without copying server-scale machinery into the app.

### mlx-swift-lm

Current mainline separates prompt reconciliation into explicit decisions such as append suffix, rewind to a common prefix, and rebuild. Strict-prefix extension is considered separately from trimmability. Newer cache infrastructure also tracks model-wide cache progress and introduces recurrent/speculative checkpoint concepts.

MINT currently resolves `mlx-swift-lm 3.31.3`. Stable `3.31.4` contains relevant Qwen3.5 recurrent-cache, Gated Delta correctness, and prompt-prefill improvements, while the larger policy/staged-round work remains mainline and should not be treated as a stable dependency contract yet.

### vLLM

Hybrid/Mamba prefix caching is treated as a state-management problem rather than ordinary arbitrary KV rewind. Aligned state checkpoints and replay are used where the recurrent representation cannot be reconstructed by deleting arbitrary trailing tokens.

### SGLang

Attention KV and auxiliary recurrent state are represented by distinct cache components. Recurrent state may be restored or copied independently of attention KV. The useful idea for MINT is state ownership/copy-on-write, not Radix-tree serving infrastructure.

### llama.cpp / ExLlamaV2 / mlx-lm

These systems likewise expose sequence branching, cache copies, page/prefix matching, or explicit prompt-cache objects rather than treating decode output and reusable prompt state as one indivisible object.

## Considered Approaches

### A. Keep current LCP/trim behavior and restrict model choices

**Pros:** minimal implementation risk; proven Basil performance.

**Cons:** rejects otherwise strong writing models because of runtime limitations; full-prefills common append-only edits on hybrid models; makes model identity leak into architecture decisions.

**Decision:** reject as the long-term 0.2.0 direction.

### B. Replace MINT with a Radix/Paged prefix-cache system

**Pros:** general prefix matching and reuse similar to high-throughput servers.

**Cons:** solves multi-request server scheduling that MINT does not have; increases memory ownership, eviction, block management, and correctness complexity dramatically.

**Decision:** reject for 0.2.0 and likely unnecessary for a single-user editor hot path.

### C. Introduce a small capability-aware Prompt State Manager

Use three reconciliation decisions — append, rewind, rebuild — and preserve a precise token ledger for the state that is considered authoritative. Add speculative prompt/decode separation only where benchmark evidence justifies it.

**Pros:** directly solves MINT's actual editing trajectory; preserves current Basil path; supports hybrid append reuse; remains testable and small; aligns with upstream direction.

**Cons:** requires careful lifecycle/cancellation correctness and benchmark proof for any state copy/fork path.

**Decision:** recommended and selected.

## Architecture

The target boundary is conceptually:

```text
ContextAssembler
      │
      ▼
 full prompt tokens
      │
      ▼
PromptReusePolicy  ───────────────┐
      │                           │
      ├─ appendSuffix             │
      ├─ rewindToCommonPrefix     │
      └─ rebuild                  │
      │                           │
      ▼                           │
PromptStateManager                │
      │                           │
      ├─ representedTokens        │
      ├─ model identity           │
      ├─ realized cache/state     │
      ├─ logical progress         │
      └─ telemetry                │
      │
      ├──── authoritative prompt state
      │
      └──── optional working/forked decode state
                         │
                         ▼
                  Ghost Completion
```

`PromptReusePolicy` must be pure and independent of MLX so its complete decision table can be tested without loading a model.

`PromptStateManager` owns mutable MLX state and applies the policy result safely.

## Reuse Policy

Policy order is intentional.

### 1. Append suffix

If the requested token stream strictly extends the exact represented token stream:

```text
represented = ABC
requested   = ABCDEF
```

select:

```text
appendSuffix(start: 3)
```

This path must not require arbitrary cache trimmability. It is allowed only when the token ledger and realized state are known to be aligned and no other model/input state makes partial continuation unsafe.

### 2. Rewind to common prefix

If the prompt diverges, compute the LCP and use the existing trim behavior only when every relevant cache/state component can perform the required rewind exactly.

```text
represented = ABCDEF
requested   = ABCXYZ
                  ^ divergence

rewind -> ABC
prefill -> XYZ
```

No model-name allowlist may stand in for a capability check.

### 3. Rebuild

Any unproven or mismatched case selects fresh prefill:

- zero useful prefix,
- non-rewindable divergence,
- state/token-ledger mismatch,
- model switch,
- incompatible cache topology/configuration,
- partial rewind result,
- corrupted/cancelled state whose exact represented prompt cannot be proven.

Correctness always wins over cache reuse.

## State Ownership

The durable runtime invariant is:

```text
User-authored prompt state = authoritative
Ghost-generated state      = speculative
```

The current cache is mutated by both prompt prefill and Ghost decoding and later repaired by trimming. This remains valid for the existing pure-attention path and does not need to be removed merely for architectural purity.

For hybrid/non-rewindable state, however, a production optimization may maintain a canonical prompt state and run Ghost decode against a copy, snapshot, or staged working state:

```text
canonical prompt state
        │
        ├─ user suffix -> advance canonical
        │
        └─ fork/snapshot -> decode working state -> Ghost
```

This is **not automatically enabled**. The implementation must first measure copy/snapshot cost, peak unified memory, and fresh-prefill cost on representative hardware/models. If copying is too expensive, append-only reuse may still be valuable while Ghost decode uses another safe strategy.

## Dependency Strategy

### Required evaluation

Evaluate `mlx-swift-lm 3.31.4` from the current `3.31.3` baseline before changing MINT's cache semantics.

The upgrade is accepted only if:

- the project builds and tests cleanly,
- current baseline models still load and generate correctly,
- existing Basil warm reuse does not materially regress,
- no new memory/lifecycle regression is observed.

### Explicit non-decision

Do not pin MINT 0.2.0 to `mlx-swift-lm` main solely to consume unreleased `PromptCacheReusePolicy`, `KVCachePlan`, or staged-round internals. MINT may mirror their design principles through a small local abstraction and migrate toward stable upstream APIs later.

## Historical Prewarm Audit

MINT documentation describes an A+B idle prefix-prewarm flow after background indexing, and Git history shows that such an implementation existed, but the current main source no longer contains the corresponding `prewarmPrefix` / `prewarm` path.

#149 must resolve this source/document drift explicitly:

1. determine whether idle prewarm still matches the 0.2.0 architecture;
2. if useful, restore it through the new prompt-state boundary with exact-state checks;
3. otherwise remove/update stale documentation and record why it is intentionally absent.

A release must not claim a prewarm behavior that does not exist in source.

## Observability

Every benchmarkable reuse decision should expose enough evidence to explain latency rather than merely report it.

Minimum fields:

```text
cacheStrategy      append / rewind / rebuild
cacheMissReason    reason for rebuild or lost reuse
promptTokens       full prompt size
reusedTokens       skipped prefill
prefilledTokens    newly evaluated prompt tokens
prefillMs          prompt evaluation time
copyMs             snapshot/fork time when present
TTFC               first visible Ghost chunk
peakMemory         where measurable
```

The exact public/internal type names may differ, but equivalent evidence must be available to MINTBench.

## Benchmark Matrix

MINTBench must cover trajectories that resemble real editing, not only two identical cold/warm invocations:

1. append typing;
2. repeated append typing;
3. one-character backspace;
4. larger backspace;
5. middle edit;
6. rapid cancellation;
7. Ghost reject;
8. Ghost accept followed by another completion;
9. crossing the current 512 recent-context boundary;
10. Story Knowledge snapshot refresh;
11. document switch and return;
12. model switch.

At minimum compare the current Basil baseline and one representative hybrid model at realistic prompt sizes. Qwen3.8-class models should be evaluated when supported by the selected stable MLX dependency, but #149 must not hard-code its contract to one model family.

## Correctness Tests

### Pure policy tests

Without MLX/model loading, prove:

- strict extension selects append;
- identical/no-suffix prompts choose a defined safe path;
- divergence selects rewind only when allowed;
- non-rewindable divergence rebuilds;
- zero-prefix mismatch rebuilds;
- model/state mismatch rebuilds;
- policy never depends on model ID.

### Cache/state tests

Using deterministic fixtures or minimal supported model probes, prove:

- cached append output/logits agree with fresh-prefill behavior within the expected deterministic tolerance;
- rewind output agrees with fresh prefill for supported cache topologies;
- partial/heterogeneous rewind cannot be committed;
- cancellation cannot cause generated Ghost tokens to become represented authoritative prompt tokens;
- any forked working state cannot mutate the canonical state after rejection/cancellation.

### Regression tests

Preserve existing model lifetime, shutdown, prompt-cache cancellation, Hangul/keyboard, and MINTBench behavior unless the new design explicitly replaces the tested contract.

## Optional 0.2.0 Anchor

If benchmarks show that non-rewindable middle edits remain an important latency cliff, #149 may add a **single stable anchor + one active state** design.

This must remain bounded:

```text
stable anchor -> replay suffix -> active state
```

The anchor should align with an already-stable prompt/context boundary and must be validated against the actual full prompt token sequence; string or independently tokenized block boundaries are not assumed to be token-concatenation safe.

Do not build a general multi-document cache bank in 0.2.0.

## Failure Handling

All cache optimization is fail-closed.

- If exact represented tokens cannot be proven, rebuild.
- If a required rewind reports incomplete progress, discard the candidate state and rebuild.
- If a state copy/snapshot cannot be proven independent, do not use it as canonical/working separation.
- If model dependency changes alter cache semantics, preserve correctness first and report lost reuse through telemetry.
- Busy/overlapping operations must never share unsynchronized mutable cache state.

## Rollout

Implementation should land in reviewable slices rather than one large refactor:

1. dependency/baseline proof;
2. pure policy + telemetry;
3. append-only capability path while preserving legacy rewind;
4. trajectory benchmarks/correctness oracle;
5. hybrid fork/checkpoint spike and production decision;
6. optional bounded anchor only if benchmark evidence requires it;
7. documentation and #119 release-gate evidence.

A failed experimental fork/checkpoint optimization is an acceptable result if the measurements are retained and the safe append/rewind/rebuild architecture remains.

## Non-Goals for 0.2.0

- Radix tree or generalized prefix-trie serving cache;
- Paged KV allocator;
- multi-document hot-state LRU;
- disk persistence on the typing path;
- custom Mamba/Gated Delta kernels;
- arbitrary recurrent rewind;
- large checkpoint banks;
- model-ID-specific cache behavior;
- speculative decoding as a product feature unless independently justified.

## Acceptance Criteria

- Strict token-prefix extension can reuse exact cached prompt state without requiring arbitrary trim when the realized state is otherwise safe.
- Divergent prompts reuse LCP only when exact rewind is supported; otherwise they rebuild.
- The existing Basil pure-attention warm path has no material latency/reuse regression.
- At least one hybrid-model benchmark records append-reuse behavior versus fresh prefill, or records a concrete dependency/support blocker without weakening correctness.
- MINTBench explains each run with reuse strategy and miss reason.
- Deterministic cached/fresh correctness checks cover supported trajectories.
- Cancellation, Ghost rejection, document changes, and model changes cannot publish or carry stale speculative state.
- Historical prewarm source/document drift is resolved.
- `swift test` and release build pass.
- #119 can consume the benchmark/correctness evidence as a release-readiness gate.
