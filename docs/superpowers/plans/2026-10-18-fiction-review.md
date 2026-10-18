# Fiction evidence Review implementation plan

Execute inline with superpowers:executing-plans, regression-first and inline author review; owner-delegated recommended choices/no subagents/repeated approval. Spec: `docs/superpowers/specs/2026-10-18-fiction-review-design.md`. This is the Fiction sub-project; #114 remains open for subsequent #126 document/project-wide Writing Quality integration and all required delivery CI.

## Task1: Prepared original-backed Fiction Review issues
Create Workspace/Review/ReviewIssue.swift, FictionReviewProjection.swift and focused tests. Consume captured ProjectDocumentSnapshot, matching KnowledgeSnapshot and current ContinuityCandidates; produce private immutable issues/category counts/stable ordering.
- [x] Compile/run regression RED for all six real producers, neutral semantic/open-thread/uncertain-structure handling, raw original/scope/revision/duplicate/cap/cancellation refusal and stable ordering/dedup across reindex.
- [x] Implement literal original factories and bounded pure prepared projection; no view, model or writer mutation.
- [x] Focused/full/build/bench and separate inline review.
- [ ] Bounded sequential PR/main CI.

## Task2: Durable Review disposition via the existing writer owner
Create ReviewDisposition.swift/service and tests; keep existing WriterDocumentData schema/ProjectWriterEditing. Consume prepared issue and current runtime; produce explicit namespaced intentional/dismissed decisions, matching suppression/history and restore.
- [ ] RED→GREEN reload/reindex/source-offset/project/ABA behavior, unrelated decisions retained, restored issues, selected-document/full-original/stale/corrupt-schema refusal and unchanged manuscript/style data.
- [ ] Use only current owner writes and preserve durable original decisions; never automatic canon or style preferences.
- [ ] Focused/full/build/bench, component review and bounded sequential PR/main CI.

## Task3: Generic exact original native navigation
Extract Map's source target/mapping into generic Editor original-source types; retain Map wrappers and existing tests. Add Review source actions with inspected-epoch/project/original checks and fresh runtime after explicit document selection.
- [ ] RED→GREEN exact same/cross-document original passage and duplicate/formatted/Unicode source jump/return, stale/native/IME/ABA refusal, unchanged editor/Undo/selection and complete source errors.
- [ ] No fuzzy source authority, Markdown/native coordinate substitution or unrelated behavior.
- [ ] Focused/full/build/bench, component review and bounded sequential PR/main CI.

## Task4: Project-owned pinned inspector and real bounded judge connection
Create FictionReviewController/runtime tests. Consume real session activeProject mutation epochs, optional inspected-document indexer snapshots/candidates, dispositions and requests.judgeSupport; produce cancellable prepared inspection, category/selected-position state and explicit judged result.
- [ ] RED→GREEN source-navigation pin/return retention, explicit retarget, edits/project/mode/corrupt ownership, noncooperative publication, policy/foreground pause and no-model/no-auto-judgment behavior.
- [ ] Cancel/clear judge at retirement; validate packet/candidate/original/inspection epoch before warning display; no automatic model setup/resume or writer action.
- [ ] Focused/full/build/bench, whole-feature source review and bounded sequential PR/main CI.

## Task5: Actual Fiction Review shell and native evidence/actions
Create Workspace/Review/ReviewView.swift; minimally attach actual indexer/runtime/support through WorkspaceSurface and expose Fiction Review mode. Consume prepared inspector and source/write APIs; present category summary, ordered issues, A/B originals, current inspected document/retarget, intentional/resolved/restore, source return and optional explicit ready judge.
- [ ] Actual synthetic ContentView/model-free source/compare/action/return/project and writer-store regressions fail before attachment; keep General Outline/Map paths and editor mounted.
- [ ] Native source/action controls with stable identity/keyboard metadata, opaque paper and quiet empty/unavailable states; no chat or analysis on view open.
- [ ] Focused/full/build/bench, whole-feature inline review and sequential PR/main all-three CI. Record Fiction implementation separately; do not close #114 before following Writing Quality sub-project and final CI/native qualification.

Review focus: actual producer provenance; neutral versus asserted conflict; original versus prose/derived identity; stable durable selected-owner decisions; independent inspection/editor epochs and source-return position; foreground/policy/stale cancellation; true runtime/UI consumption. No unresolved plan issue or orphan interface.
