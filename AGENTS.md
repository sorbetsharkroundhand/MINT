# MINT — Agent Constitution

MINT is a **local AI writing platform, Fiction First** for macOS (SwiftUI + AppKit + MLX). General Writing is a first-class path; Fiction is the deepest specialization.

Read:
- `PLAN.md` for architecture/current roadmap.
- `docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md` for the 0.2.0 product contract.
- Child issue for the exact implementation/acceptance contract.

## Build / run

- Type/build check: `swift build`
- Tests: `swift test`
- Bench compile: `swift build --product MINTBench`
- App bundle: `scripts/build-mint-app.sh`
- Smoke: `scripts/smoke-mint-app.sh`
- UI smoke: `scripts/ui-smoke-mint-app.sh`
- Runtime MLX may require `scripts/prepare-metallib.sh`; plain SwiftPM output can lack the required metallib.
- UI smoke isolation uses **`CFFIXED_USER_HOME`**. `$HOME` alone is not sufficient.

## Product invariants

1. **Writing Platform, Fiction First.** `WritingProject` is generic; Fiction-specific types stay below the platform layer.
2. **Editor first.** AI is optional. Keep the core editor good without a model.
3. **Local only.** No remote inference or telemetry.
4. **User data wins.** Manuscript + User Canon are durable. AI-derived Intelligence is rebuildable.
5. **Evidence first.** Important warnings must resolve to original manuscript evidence.
6. **Quiet AI.** Prefer silence over low-confidence interruption.
7. **Foreground prediction wins.** Background indexing/judging yields or cancels immediately.
8. **Incremental by default.** Full rebuild is recovery, not the normal path.
9. **No future leakage.** Cursor-bounded context excludes later story knowledge.
10. **Selective Liquid Glass.** Editor body is opaque; glass is semantic chrome/transient intelligence, never a nested default container style.

## Editor invariants

- Preserve Hangul IME composition. Never trigger Ghost while marked text is active.
- Preserve Ghost `Tab` accept / `→` partial accept / `Esc` reject.
- Preserve cursor-line highlight.
- Preserve undo, autosave/recovery, Markdown/EPUB/media/math round-trip.
- Prediction hot path performs no disk scan, retrieval LLM call, or background rebuild.
- Do not let shell/docking/panel transitions steal editor first responder unless explicitly invoked.

## Architecture boundaries

- Generic project/storage: `Sources/MINTCore/Project/`
- Story knowledge/retrieval/continuity: `Sources/MINTCore/Knowledge/`
- Fiction-only domain: `Sources/MINTCore/Fiction/`
- Editor engine: `Sources/MINTCore/Editor/`
- Ask MINT: `Sources/MINTCore/Agent/`
- Do not add Knowledge responsibilities to `BlockTextView` or `EntryStore`.
- Derived `DocumentOutline.Scene` hashes are not persistent manuscript IDs.
- Existing `SourceAnchor` is a re-anchoring utility; cross-layer evidence uses `EvidenceAnchor`.

## Concurrency / background work

Every background task must:
- cooperate with cancellation;
- be project/generation scoped;
- avoid stale publication;
- obey thermal/low-power gates where relevant;
- memoize by content hash where applicable;
- stay below foreground Ghost priority.

## Storage safety

- Never modify legacy `entries.json` in place during 0.2.0 migration.
- Verify a new project before activation.
- Failure must leave the previous valid manuscript/project usable.
- Block path traversal/symlink escape.
- Derived `Intelligence/` may be deleted/rebuilt without losing user data.

## Git / delivery

- Keep `main` buildable.
- Prefer one child issue = one reviewable PR.
- New behavior: failing test → minimal fix → regression coverage → refactor.
- Do not mark an issue complete before main merge + CI/E2E evidence.
- Replacement surface must land before removing legacy primary UI.
- Before modifying a stale branch, compare it with current `main`; do not overwrite unrelated work.

## Documentation language / token budget

- **Repo docs, plans, issue titles/bodies, PR descriptions, and implementation comments default to English.**
- User-facing UI copy may remain Korean/localized where product design requires it.
- Korean may appear in fixtures only when the test specifically validates Korean/IME/Unicode behavior.
- Keep canonical docs concise; move historical logs to PRs/issues rather than repeating them in `PLAN.md`.
