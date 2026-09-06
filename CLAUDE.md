# MINT — Claude Code Guide

MINT is a **local AI writing platform, Fiction First**.

Canonical references:
1. `AGENTS.md` — universal implementation invariants.
2. `PLAN.md` — architecture + current roadmap.
3. `docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md` — 0.2.0 product contract.
4. The active child issue — exact scope and acceptance criteria.

## Non-negotiable rules

- Preserve Hangul IME, cursor-line highlight, Ghost `Tab/→/Esc`, undo/recovery, export/media round-trip.
- Local-only AI; no telemetry.
- Prediction hot path: no disk scan, retrieval LLM call, or knowledge rebuild.
- Foreground Ghost preempts background Intelligence.
- Manuscript/User Canon are durable; derived Intelligence is rebuildable.
- No future story knowledge in cursor-bounded prediction/context.
- Important warnings require resolvable original `EvidenceAnchor`.
- Generic platform code must not depend on Fiction-specific types.
- Keep `BlockTextView` focused on editing; Knowledge logic belongs under `Knowledge/`.
- Use selective Liquid Glass: opaque editor, restrained chrome, no stacked glass.
- UI smoke must use `CFFIXED_USER_HOME`; never test against real user manuscripts.

## Commands

```bash
swift test
swift build
swift build --product MINTBench
scripts/build-mint-app.sh
scripts/smoke-mint-app.sh
scripts/ui-smoke-mint-app.sh
```

If MLX runtime shaders are missing, run `scripts/prepare-metallib.sh`.

## Delivery

- Re-sync with current `main` before coding.
- Prefer one issue / one reviewable PR.
- Use tests as the implementation contract.
- Never weaken CI to make a change pass.
- Completion means merged to main with CI/E2E evidence.

## Language

Use English for repo docs, plans, issues, PR text, and implementation comments. Keep Korean only for localized UI copy or tests that explicitly validate Korean/IME/Unicode behavior.
