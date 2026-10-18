# Original-backed consistency implementation plan

> Execute inline with superpowers:executing-plans, regression-first; no subagents or repeated approval.

**Goal:** Preserve legacy dead-speaker/honorific behavior while publishing only current original-backed, non-shifted candidates.
**Architecture:** Add one original-aware checker file, small warning evidence field, two existing background call-site arguments and an exact navigation gate. Leave storage, inference and prediction untouched.
**Tech stack:** Swift/Foundation, existing DocumentOutline/DialogueAttribution/EvidenceAnchor, XCTest.
**Spec:** `docs/superpowers/specs/2026-10-17-consistency-evidence-design.md`.

## Global constraints
No local product launch, real model operation, subagents, user data mutation, dependency change or CI weakening. Model choice/native acceptance remain manual; #109 is partial until the other rules ship.

## Review focus
1. An unverified newer state or competing same-scene values must not resurrect an old death assertion.
2. A suppressed flashback or uncertain sample must not consume deduplication or establish current honorific usage.
3. Duplicate IDs/quotations, composed Unicode lookalikes and invalid offsets must refuse without crashes or fuzzy navigation.
4. Source changes/cancellation never expose partial stale proof; background publication ownership remains intact.
5. Legacy API tests stay green while both actual publication paths use the new original-aware overload.

### Task 1: Evidence-aware candidate production and original navigation
**Files:** Create `Sources/MINTCore/Knowledge/ConsistencyEvidenceChecker.swift`, `Tests/MINTCoreTests/ConsistencyEvidenceTests.swift`; modify ConsistencyChecker warning/equality/death vocabulary, BackgroundIndexer call sites and NarrativeView source navigation.
**Consumes:** Current KnowledgeSnapshot, registered CharacterCard values and captured original String.
**Produces:** `ConsistencyChecker.check(snapshot: KnowledgeSnapshot, characters: [CharacterCard], source: String) -> [ConsistencyWarning]` and `ConsistencyWarning.sourcePosition(in: String, documentID: WritingDocumentID) -> Int?`.

- [x] Write source-backed tests for positive dead/honorific checks, four proof anchors, negation, shifted scenes/segments, unknown/newer unverified/conflicting state, duplicates/raw Unicode/stale source, cancellation and navigation refusal; run and retain RED.
- [x] Implement exact original context and conservative state/streak pass in the new file; add evidence default for legacy source compatibility and close affirmative death vocabulary. Route both captured-body publications and exact current-document navigation and synchronous edit retirement, including memory pressure; preserve generation/IME/undo/focus paths.
- [x] Run focused consistency/lifecycle/source tests, locked build/full tests/MINTBench in isolated CFFIXED_USER_HOME. Review all five focus conditions inline, reproduce/fix Important findings before final verification.
- [x] Commit bounded PR after predecessor merge, attach it; merge only after exact-head and predecessor-main all-three CI plus fresh feedback. Verify final merged-main all-three and record partial #109 progress without closing other rules.

Plan self-review: all spec requirements map to Task1; focused regressions include every review-focus input, no disconnected new rule producer or invented time units. Keep new rule/extraction work as the next architectural sub-project.
