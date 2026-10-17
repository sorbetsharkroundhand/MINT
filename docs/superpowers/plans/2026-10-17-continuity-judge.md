# Evidence-bounded judge implementation plan

> Execute inline with superpowers:executing-plans, regression-first, no subagents/repeated approval.

**Goal:** Judge one explicit scoped continuity candidate using only bounded original evidence and a ready local model.
**Architecture:** Immutable packet/strict single-record decoding precedes ticketed cancellation-safe request/runtime support. Reuse existing instruction transport/drain and actual engine; Review/Margin UI remains #114/#270.
**Tech stack:** Swift/Foundation/CryptoKit/Combine/XCTest; no new dependencies.
**Spec:** `docs/superpowers/specs/2026-10-17-continuity-judge-design.md`.

## Global constraints
No local MINT launch, actual model selection/download/inference, native acceptance, user-data mutation, hot-path scans or CI weakening. Low/malformed/unresolved judgments stay quiet. No automatic canon or resume.

## Review focus
1. Quoted instructions, Unicode lookalikes, duplicate/root-escaped keys and citation prose must never grant source authority.
2. Current original evidence and runtime/nonce checks remain independent; identical A→B→A bodies cannot revive old output.
3. Incomplete/malformed/trailing/overflow output never becomes a partial or uncited conflict.
4. Foreground/policy/model/master changes retire decisions first, cancel/drain real producers and never auto-resume.
5. Supplemental instructions cannot claim an already-busy model, select/load one or reuse Ghost state.

### Task 1: Immutable original packet and strict verdict decoder
**Files:** Create `Knowledge/JudgeEvidencePacket.swift`, `Knowledge/JudgeDecision.swift`, `Tests/MINTCoreTests/ContinuityJudgePacketTests.swift`.
**Consumes:** ContinuityCandidate, ProjectDocumentSnapshot, EvidenceAnchor and current original hashes.
**Produces:** `JudgeEvidencePacket.prepare(candidate:document:) throws`, `.userMessage()` and `JudgeDecision.decode(_:packet:) throws`, with `.visibleConflict` and real `.evidence` anchors.
- [x] Write/run failing literal source/scope/time/origin/nonce/bounds, closed root/duplicate JSON, confidence/citation/verdict/partial/size tests; include flashback noConflict and intentionalPossible cases.
- [x] Implement private factory, complete-line excerpt, bounded numbered originals/JSON data and strict single-object decoder. No model/controller/UI work yet.
- [x] Run focused/full/build/bench and separate inline review; fix Important findings RED→GREEN.
- [ ] Commit bounded PR after predecessor merge, attach; require all predecessor-main, exact-head and merged-main CI plus fresh feedback.

### Task 2: Explicit cancellable request and real runtime support
**Files:** Create `Knowledge/ContinuityJudgeController.swift`, `Knowledge/ContinuityJudgeSupport.swift`, focused controller/lifetime tests; extend CompletionController/ProjectEditorRequests/ContentView ready-support attachment and ModelLifetimeCoordinator supplemental admission only.
**Consumes:** Task1 packet/decision and existing AskAnswerGeneration ordered/drain transport plus CompletionEngine.streamInstructionIfReady.
**Produces:** ticketed single-candidate controller, `.makeContinuityJudgeSupport()` from the actual private engine and optional requests support for #114/#270.
- [ ] Write/run failing valid/quiet/malformed stream, noncooperative cancellation/drain, A→B→A, edit/master/model/policy/foreground, active ready-operation refusal and unloaded-engine tests.
- [ ] Implement explicit request ownership and complete-only publication; observe runtime/gates and attach the same already-ready engine without inference on open. Ready admission refuses nonzero active operations.
- [ ] Run final focused/full/build/bench and whole-feature inline review of all five conditions. Keep semantic/native/actual-visible-workflow evidence separate.
- [ ] Deliver sequential PR/main CI and record #110 implementation only on verified main; preserve #114/#270/#119 remaining UI/native evidence.

Plan review: no orphan packet/decoder/support interface, no autonomous exploration or writer action. Every review-focus class maps to an explicit regression gate. The real backend is required alongside fake stream coverage; actual model/native quality remains owner-later.
