# Prompt-State Reuse Architecture — Design Specification

> **Issue:** #149 — Make prompt-state reuse capability-aware for hybrid caches
>
> **Milestone:** MINT 0.2.0
>
> **Parent contract:** `docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md`

## Goal

Evolve MINT's Ghost Completion cache layer from a single LCP-and-trim optimization into a small, capability-aware **prompt-state reuse architecture**.

The 0.2.0 production slice is deliberately narrow:

1. evaluate the stable `mlx-swift-lm 3.31.4` dependency;
2. separate prompt reconciliation into `appendSuffix`, `rewindToCommonPrefix`, and `rebuild`;
3. allow exact append-only reuse without requiring arbitrary trim;
4. preserve the current pure-attention LCP/trim fast path;
5. expose enough telemetry and trajectory tests to prove correctness and latency.

Canonical/decode state forking, recurrent checkpoints, cache banks, and anchor/replay are **not required production work in #149**. They may be measured or documented as follow-up directions after the core policy lands.

The product-level reason is simple: model selection should be driven primarily by writing quality, not by whether a model's cache topology happens to fit today's `PromptCacheBox` implementation.

## Current State

MINT already has a strong continuation-specific cache path:

- `ContextAssembler` keeps stable project/context information before recent manuscript text.
- The editor keeps the recent-text window start stable on a 512 UTF-16 grid to preserve prompt locality while typing.
- `PromptCacheBox` stores one live `[KVCache]`, the most recently committed prompt-token ledger, and model identity.
- A new continuation computes the longest common prefix against the recorded prompt.
- Reuse is accepted only when `canTrimPromptCache(cache)` is true.
- The live cache is trimmed from its actual offset back to the LCP, which also removes generated or cancelled tail state.
- Only the requested suffix is then prefilled.
- Any unsafe state falls back to a fresh cache.

This is effective for trimmable pure-attention caches and must remain the fast path for models such as the current Basil baseline.

## Problem

The current implementation conflates **forward extension** with **backward reconciliation**.

Given:

```text
cached:    ABC
requested: ABCDEF
```

MINT still requires the entire cache to be trimmable, even though no backward operation is needed. A recurrent or hybrid state can often advance from an exact represented prefix to `ABCDEF`; it simply cannot recover an arbitrary earlier state such as `AB` after later state has been committed.

The accurate limitation is therefore:

> MINT's current arbitrary-LCP-rewind path cannot reuse a non-trimmable recurrent cache after divergence, but exact append-only continuation does not intrinsically require rewind.

This distinction matters for modern Gated Delta / Mamba-style hybrid models.

## Ecosystem Findings

The design follows current inference-engine principles without copying server-scale machinery into MINT.

### mlx-swift-lm

Current mainline separates prompt reconciliation into explicit append, rewind-to-common-prefix, and rebuild decisions. Strict-prefix extension is considered separately from trimmability. Newer mainline infrastructure also tracks model-wide cache progress and explores recurrent/speculative checkpoints.

MINT currently resolves `mlx-swift-lm 3.31.3`. Stable `3.31.4` contains relevant Qwen3.5 recurrent-cache, Gated Delta correctness, and prompt-prefill improvements. The larger mainline cache-policy/staged-round work is not yet treated as MINT's stable dependency contract.

### vLLM

Hybrid/Mamba prefix caching is treated as a state-management problem rather than ordinary arbitrary KV rewind. Aligned state checkpoints and replay are used where a recurrent representation cannot be reconstructed by deleting arbitrary trailing tokens.

### SGLang

Attention KV and auxiliary recurrent state are represented by distinct cache components. Recurrent state may be copied or restored independently. The useful idea for MINT is state ownership/copy-on-write, not Radix-tree serving infrastructure.

### llama.cpp / ExLlamaV2 / mlx-lm

These systems expose sequence branching, cache copies, page/prefix matching, or explicit prompt-cache objects rather than treating decode output and reusable prompt state as one indivisible object.

## Considered Approaches

### A. Keep current LCP/trim behavior and restrict model choices

**Pros:** minimal implementation risk; proven Basil performance.

**Cons:** rejects otherwise strong writing models because of runtime limitations; full-prefills common append-only edits on hybrid models; makes runtime constraints dominate model quality.

**Decision:** reject as the 0.2.0 direction.

### B. Replace MINT with a Radix/Paged prefix-cache system

**Pros:** generalized prefix matching and reuse similar to high-throughput servers.

**Cons:** solves multi-request scheduling MINT does not have; adds block allocation, eviction, ownership, and correctness complexity far beyond the editor hot path.

**Decision:** reject.

### C. Introduce a small capability-aware prompt-reuse policy

Keep one active prompt state, make prompt reconciliation explicit, and use exact token/state evidence to choose append, rewind, or rebuild.

**Pros:** directly solves MINT's real typing trajectory; preserves Basil; enables hybrid append reuse where safe; small enough for one reviewable 0.2.0 slice; pure decision logic is easy to unit test.

**Cons:** does not optimize arbitrary middle edits on non-rewindable recurrent state in this issue.

**Decision:** selected.

## 0.2.0 Architecture

The required architecture is:

```text
ContextAssembler
      │
      ▼
 full prompt tokens
      │
      ▼
PromptReusePolicy
      │
      ├─ appendSuffix
      ├─ rewindToCommonPrefix
      └─ rebuild
      │
      ▼
PromptStateManager / evolved PromptCacheBox
      │
      ├─ representedTokens
      ├─ model identity
      ├─ realized cache
      └─ decision telemetry
      │
      ▼
CompletionEngine
      │
      ▼
Ghost Completion
```

The implementation may evolve `PromptCacheBox` in place or rename it if the new boundary is materially clearer. A rename alone is not a goal.

`PromptReusePolicy` must be pure and independent of MLX so its decision table can be tested without loading a model.

The mutable owner applies the policy to MLX state and remains fail-closed.

## Reuse Policy

Policy order is intentional.

### 1. `appendSuffix`

If the requested token stream strictly extends the exact represented token stream:

```text
represented = ABC
requested   = ABCDEF
```

select:

```text
appendSuffix(start: 3)
```

This path does **not** require arbitrary cache trimmability. It is allowed only when:

- the model identity matches;
- the represented-token ledger is exact for the reusable state;
- the cache/state has not been invalidated by an error or incompatible operation;
- the input shape/state permits suffix prefill safely.

The concrete 3.31.4 API may limit which hybrid topologies MINT can prove safe. When proof is unavailable, the decision must fall back to rebuild rather than using model-name assumptions.

### 2. `rewindToCommonPrefix`

If the prompt diverges, compute the LCP and preserve the existing trim behavior only when the whole relevant cache topology can perform the required rewind exactly.

```text
represented = ABCDEF
requested   = ABCXYZ

rewind -> ABC
prefill -> XYZ
```

This remains the Basil/pure-attention fast path.

### 3. `rebuild`

Any unproven or mismatched case selects fresh prefill:

- zero useful prefix;
- non-rewindable divergence;
- state/token-ledger mismatch;
- model switch;
- incompatible cache topology/configuration;
- partial rewind result;
- failure/cancellation state whose represented prompt cannot be proven exact.

Correctness always wins over reuse.

## Prompt-State Invariant

The conceptual invariant remains:

```text
User-authored prompt state = authoritative
Ghost-generated state      = speculative
```

#149 does **not** require changing the current generated-tail cleanup mechanism if the existing trim path remains correct for that topology. The issue first fixes reconciliation policy, not every internal ownership mechanism.

A future optimization may separate canonical prompt state from a copied/staged decode state, but only after memory/copy cost and correctness are measured. That follow-up must not block the required 0.2.0 slice.

## Dependency Strategy

Evaluate `mlx-swift-lm 3.31.4` from the current `3.31.3` baseline before changing MINT's reuse semantics.

Accept the upgrade only if:

- `swift test` and release build remain green;
- current baseline models still load and generate correctly;
- Basil's existing warm reuse does not materially regress;
- no new lifecycle or memory regression appears in the existing benchmark/smoke path.

Do not pin MINT 0.2.0 directly to upstream `main` solely to consume unreleased cache-policy or staged-round internals. MINT can adopt the stable design principle locally and migrate to released upstream APIs later.

## Required Observability

MINTBench must be able to explain why a request was warm or cold.

Required evidence:

```text
cacheStrategy      append / rewind / rebuild
cacheMissReason    reason for rebuild or lost reuse
promptTokens       full prompt size
reusedTokens       skipped prefill
prefilledTokens    newly evaluated prompt tokens
TTFC               first visible Ghost chunk
```

Add `prefillMs` if the current generation API exposes a reliable measurement without invasive instrumentation. Copy/snapshot timing is a follow-up field because production copy/fork is not required by #149.

## Required Benchmark Trajectories

Extend MINTBench beyond identical cold/warm invocations with deterministic editing trajectories:

1. strict append typing;
2. repeated append typing;
3. backspace/divergence;
4. middle edit;
5. rapid cancellation;
6. crossing the current 512 recent-context boundary;
7. Story Knowledge/context-prefix refresh when the corresponding fixture can be constructed deterministically;
8. model switch.

Document switch/return and Ghost accept/reject may be covered by controller/lifecycle tests if they are awkward to express in the CLI harness; they do not justify building a multi-document cache pool in #149.

At minimum compare the existing Basil baseline with one representative hybrid model that is supported by the selected stable dependency. The issue contract must not depend on a specific Qwen model being loadable.

## Testing

### Pure policy tests

Without MLX/model loading, prove:

- strict extension selects append;
- identical/no-suffix input chooses a defined safe path;
- divergence selects rewind only when allowed;
- non-rewindable divergence rebuilds;
- zero-prefix mismatch rebuilds;
- model/state mismatch rebuilds;
- policy never depends on model ID.

### Mutable-state tests

Prove:

- append does not first invoke an unnecessary trim requirement;
- supported rewind trims exactly the requested amount;
- incomplete rewind is never accepted;
- failed/cancelled state cannot be recorded as a reusable exact prompt when that exactness is unproven;
- model switch invalidates reuse as today.

### Regression evidence

Preserve existing model lifetime, shutdown, prompt-cache cancellation, editor IME/keyboard, and current Basil benchmark behavior unless this issue explicitly supersedes a tested contract.

Where practical, a deterministic cached path should be compared against fresh prefill as a correctness oracle. Real-model oracle work that cannot be made deterministic belongs in benchmark evidence rather than brittle unit tests.

## Historical Prewarm Drift

Git history and current documentation disagree about the A+B idle prewarm path: historical code implemented it, while current main no longer exposes the described `prewarmPrefix` / `prewarm` flow.

#149 must perform a bounded audit because prewarm semantics depend directly on what state is considered reusable. The required outcome is documentation truthfulness:

- if restoring prewarm is trivial and compatible with the new exact-state contract, it may land here;
- if restoration is non-trivial, open/identify a follow-up and update the stale documentation in #149 rather than expanding this issue into a second subsystem.

## Failure Handling

All optimization is fail-closed.

- Unknown exact state -> rebuild.
- Unsupported rewind -> rebuild.
- Incomplete trim -> discard candidate state and rebuild.
- Model change -> invalidate.
- Dependency behavior change -> preserve correctness and expose lost reuse in telemetry.
- Busy/overlapping operations must never share unsynchronized mutable cache state.

## Implementation Boundary

#149 should remain one reviewable production slice:

```text
3.31.4 evaluation
    ↓
PromptReusePolicy
    ↓
append / rewind / rebuild application
    ↓
strategy + miss-reason telemetry
    ↓
trajectory tests / benchmark evidence
    ↓
docs + #119 evidence
```

### Follow-up only unless required to prove the core

- canonical prompt cache + decode-state fork;
- recurrent checkpoint/restore;
- 512-aligned prompt-state anchor/replay;
- cache-copy timing/peak-memory experiments beyond what is needed to decide a later issue.

## Non-Goals for 0.2.0 #149

- Radix tree or generalized prefix-trie serving cache;
- Paged KV allocator;
- multi-document hot-state LRU;
- disk persistence on the typing path;
- custom Mamba/Gated Delta kernels;
- arbitrary recurrent rewind;
- large checkpoint banks;
- model-ID-specific cache behavior;
- speculative decoding as a product feature;
- production prompt/decode fork without a separately reviewed benchmark-backed contract.

## Acceptance Criteria

- `mlx-swift-lm 3.31.4` is either adopted with baseline evidence or explicitly rejected with a concrete compatibility/regression reason.
- Strict token-prefix extension can reuse exact cached prompt state without requiring arbitrary trim when the stable dependency exposes enough state to prove the path safe.
- Divergent prompts reuse LCP only when exact rewind is supported; otherwise they rebuild.
- The existing Basil pure-attention warm path has no material latency/reuse regression.
- At least one supported hybrid-model benchmark records append-reuse behavior versus fresh prefill, or records the exact stable-API blocker that prevents safe reuse without weakening correctness.
- MINTBench reports reuse strategy and miss reason alongside prompt/reuse evidence.
- Policy and mutable-state tests cover append, rewind, rebuild, invalidation, cancellation/failure, and partial-rewind refusal.
- Historical prewarm source/document drift is made truthful without expanding #149 into a separate prewarm subsystem.
- `swift test` and release build pass.
- #119 can consume the resulting correctness/latency evidence as an RC gate.
