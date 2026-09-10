# MINT — Agent Guide

Local macOS writing app, Fiction First; General writing and AI-disabled editing remain supported.

## Read only what the task needs
- This file contains shared invariants. Do not reread it if already present in context.
- Before planning/coding an issue, refresh the checkout and read that issue's current body plus relevant recent comments/linked active PR. Follow actual blockers, not every related issue.
- Read [release epic #99](https://github.com/sorbetsharkroundhand/MINT/issues/99) when deciding scope/dependencies; [gate #119](https://github.com/sorbetsharkroundhand/MINT/issues/119) for RC work.
- Use `PLAN.md` as an optional code/document index. Search paths/symbols, then read relevant sections.
- Historical specs, plans, benchmarks and README vision are not current implementation contracts. Read them only to answer a concrete question.
- Do not routinely fetch all open issues, unrelated PRs, or every plan/skill. Follow applicable higher-priority skill requirements; repository guidance cannot disable them.
- If sources conflict, report the specific conflict before coding. Current issue contracts take precedence over historical repo plans; user instructions remain authoritative.

## Product and data invariants
- Editor first; no model/network setup required to write. Local inference only, no telemetry.
- Generic project/storage code must not depend on Fiction types.
- Manuscript and user decisions are durable; derived Intelligence is rebuildable.
- Never migrate legacy `entries.json` in place. Verify a new project before activation; failure preserves the previous valid state.
- Reject path traversal/symlink escape. Cache cleanup must not delete user data.
- Important claims require supporting original evidence; uncertain inference stays quiet.
- Cursor-bounded completion excludes future knowledge. Explicit whole-project inspection has its own scope.
- Keep scene hashes distinct from persistent manuscript IDs; use `EvidenceAnchor` across layers and `SourceAnchor` for re-anchoring.
- Style preferences belong to `WriterStyleProfile`, not User Canon.

## Editor and execution invariants
- Preserve Hangul IME; never generate Ghost during marked text.
- Preserve Ghost Tab accept / right-arrow partial / Esc reject, cursor-line highlight, undo, autosave/recovery and Markdown/EPUB/media/math round-trip.
- Tool transitions preserve editor focus/selection unless explicitly invoked otherwise.
- No disk scan, retrieval LLM call or rebuild in prediction hot paths.
- Background tasks are cancellable, project/generation scoped, stale-safe, hash-memoized where applicable, thermal/low-power aware, and yield immediately to foreground Ghost.
- Incremental work is normal; full rebuild is load/recovery/global-restyle.
- Keep Knowledge logic out of `BlockTextView` and `EntryStore`.
- Opaque manuscript, restrained material in chrome/transient tools; no stacked glass.

## Verification and delivery
- Compile: `swift build`; tests: `swift test`; bench compile: `swift build --product MINTBench`.
- Runtime: `scripts/prepare-metallib.sh` when needed; bundle: `scripts/build-mint-app.sh`; smoke: `scripts/smoke-mint-app.sh`; UI: `scripts/ui-smoke-mint-app.sh`.
- Isolate UI tests with `CFFIXED_USER_HOME`, not HOME alone; never use real manuscripts.
- Keep main buildable; compare stale branches before editing; prefer one bounded issue/PR.
- New behavior needs failing regression coverage before implementation. Never weaken CI.
- Preserve access to user data before retiring UI. Close issues only after main merge and required CI/E2E evidence.
- Ad-hoc bundle smoke is not Store distribution proof; follow #150/#119.
- English for repo docs, issues, PRs and implementation comments; localized UI/Korean-specific fixtures may use Korean.
