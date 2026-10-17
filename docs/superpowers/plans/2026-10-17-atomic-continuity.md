# Atomic continuity implementation plan

> Execute inline with superpowers:executing-plans; regression-first, no subagents/repeated approval.

**Goal:** Produce scoped original-backed continuity candidates from verified atomic observations.
**Architecture:** Pure candidate kernels consume prepared StoryKnowledgeSnapshot values. Typed explicit unaware/age metadata preserves unknown semantics; the existing background publisher owns lifecycle and body gates.
**Tech stack:** Swift/Foundation/CryptoKit/XCTest, no new dependency.
**Spec:** `docs/superpowers/specs/2026-10-17-atomic-continuity-design.md`.

## Global constraints
No local product launch, shipping-model operation, user-data mutation, hot-path scans or CI weakening. Candidates never become canon/hard conflicts automatically. Source proof and confidence are distinct.

## Review focus
1. Missing knowledge, differing compatible roles and place aliases cannot be promoted to proven conflict.
2. Unknown/mismatched story time and future incomplete discourse cannot create overlapping-location/knowledge facts.
3. A weak or restoration observation must fence an old destroyed-state assertion.
4. Repeated evidence, integer extremes and cancelled work cannot inflate results, trap or publish partial output.
5. All actual candidate publication/retirement paths preserve current body/runtime/project ownership and editor priority.

### Task 1: Atomic candidate kernels
**Files:** Create `Knowledge/ContinuityCandidate.swift`, `Tests/MINTCoreTests/AtomicContinuityTests.swift`; extend StoryKnowledge.CharacterKnowledge.Stance.
**Consumes:** `StoryKnowledgeSnapshot.observations(before:)`, validated original scopes/evidence/time and explicit stances.
**Produces:** private-construction `ContinuityCandidate`; `ContinuityCandidate.prepare(snapshot: StoryKnowledgeSnapshot, before: Int) -> [ContinuityCandidate]`.
- [x] Write/run failing knowledge/location/relationship/object cases with original snapshots, unknown/time/future/weak/repair/dedup/cancellation/output-limit assertions.
- [x] Implement explicit unaware stance and deterministic evidence-backed bounded kernels; same-calendar age follows Task2. Candidate keys/order are stable and independent of Dictionary traversal.
- [x] Run atomic/query/legacy focused tests, build/full tests/MINTBench and separate inline review; retain Important regression fixes.
- [ ] Commit/publish/attach bounded PR after predecessor merge; require all predecessor-main, exact-head and merged-main CI plus fresh feedback.

### Task 2: Explicit age arithmetic and actual scoped preparation
**Files:** Extend Knowledge/StoryKnowledge.swift, StoryEntityResolver.swift, StoryKnowledgeSnapshot.swift, ContinuityCandidate.swift, BackgroundIndexer.swift and age/indexer ownership tests.
**Consumes:** Task1 candidate factory and current source-backed legacy warning factory.
**Produces:** `CharacterAge(characterID:completedYears:calendarYear:calendarID:)`, `.characterAge`, and `BackgroundIndexer.continuityCandidates` owned by existing snapshot publication.
- [x] Write/run failing age/calendar/overflow/unknown convention, prepared legacy candidate evidence and edit/project/paused/stale publication tests.
- [x] Add typed age validation/indexing and checked birth-year comparison; connect both real background candidate publications and synchronous edit/transition retirement without inference or source work in views/prediction.
- [x] Run focused/full/build/bench and separate whole-feature inline review of all five conditions. Record generation-only versus judge/UI/native evidence accurately.
- [ ] Deliver bounded PR with exact CI evidence; update #109 implementation scope only after main proof. #110/#270 own remaining judge/visible insights.

Plan review: both tasks have independent testable kernels and no orphan interfaces; all constraints map to a task. No schema migration, unregistered object creation, invented time units or absent-state inference is permitted.
