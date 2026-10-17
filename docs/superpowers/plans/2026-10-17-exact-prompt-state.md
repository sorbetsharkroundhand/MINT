# Exact prompt-state implementation plan

> Execute inline with superpowers:executing-plans; regression-first, no subagents, no repeated owner approval. Spec: `docs/superpowers/specs/2026-10-17-exact-prompt-state-design.md`.

## Review focus
1. Old completions/errors after invalidation cannot modify a newer lease, model or token record.
2. Every reused layer contains exactly the proven prompt prefix; first-layer success never hides another layer's failed trim/offset.
3. Unsupported recurrent/windowed/nested/custom state stays usable through fresh prefill without warm-reuse claims or model selection.
4. The engine retains drain-before-handoff, cancellation/early-stop correctness, editor-first behavior and current generation priority; no new inference or disk path.

### Task 1: Capability-checked leases at the actual generation seam

**Files:** Extend `Inference/PromptCache.swift`, update lease ownership in `Inference/CompletionEngine.swift`; create `Tests/MINTCoreTests/PromptCacheOwnershipTests.swift`. Preserve existing PromptCacheMath API and public engine API.

- [ ] Write failing deterministic ownership/capability/trim regressions. A factory-based begin seam uses the same production implementation without loading a model; retain genuine behavior RED before fixes.
- [ ] Implement captured owner/tokens and opaque leases, exact supported-layer capability inspection and all-layer post-trim proof; use leases in both engine success/cancellation/error paths after synchronization.
- [ ] Run focused prompt-cache/generation synchronization/lifetime tests, build/full tests/MINTBench; perform separate inline whole-diff review, fix Important findings with RED→GREEN evidence.
- [ ] Commit/publish/attach one bounded PR after predecessor merge; merge only after predecessor main and exact-head all-three CI plus fresh owner feedback. Synchronize clean primary main and record all-three merged-main checks before closeout. No local product/UI or shipping LLM operation.

Inline plan review: the current engine is the sole PromptCacheBox caller. A request lease replaces token-only completion without changing the public completion interface. Production capability inspection follows the pinned local MLX source; deterministic fixtures cover unsupported fallback without claiming a shipping model. Publication may overlap predecessor main CI; actual merge/closeout never skips either gate.
