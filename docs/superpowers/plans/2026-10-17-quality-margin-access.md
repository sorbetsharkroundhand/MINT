# Prepared quality margin access implementation plan

> Execute inline with superpowers:executing-plans and regression-first coverage. No subagents; owner-delegated UI/internal choices are reviewed inline. Do not ask again for an already authorized choice.

**Spec:** `docs/superpowers/specs/2026-10-17-quality-margin-access-design.md`

**Goal:** Make existing writing suggestions reachable without analysis-on-open, and navigate their exact prepared source occurrences.

**Constraints:** Editor/model-free/local-first; original UTF-16/full runtime/actual native key; IME/Ghost/focus/Undo/autosave/format invariants; no new dependency or persisted preference/schema; preserve all owner artifacts. No local Purlory/UI-smoke/LLM operation. Publish only after PR #285's merged-main CI; exact successor PR/main CI all three required jobs. Partial #270 only; native acceptance and other producers remain open.

## Review focus
1. Stale/dismissed/other-project or same-byte wrong native owners cannot navigate; neither fuzzy matches nor canonical Unicode equality grant authority.
2. Second duplicate and formatted/related evidence select their own mapped native occurrence, with exact return capture and no manuscript edit.
3. Marked text survives refused navigation; automatic publication never opens a tool or changes focus/selection.
4. Rail opening/closing and Outline/tool/project transitions keep the editor/Undo mounted, preserve existing preferences and do not start analysis.

### Task 1: Reachable quality panel and exact prepared navigation

**Files:** Extend `Workspace/WorkspaceRail.swift`, `Workspace/WorkspaceShellView.swift`, `Workspace/WorkspacePresentationState.swift`, `Intelligence/LivingMarginView.swift`, `WritingQuality/WritingDiagnosticsRuntime.swift`, `WritingQuality/WritingDiagnosticsWorkspaceBinding.swift`, `WritingQuality/WritingDiagnosticsActions.swift`; extend `FramedWorkspaceTests.swift`, `WritingDiagnosticsIntegrationTests.swift`, `WorkspaceLayoutTests.swift` and add focused margin workspace tests as useful. Existing source return is reused.

**Interfaces:** Internal LivingMarginView evidence callback receives `(MarginInsight, EvidenceAnchor)`. Runtime exposes `navigateMarginEvidence(insightID: String, evidence: EvidenceAnchor, requests: ProjectEditorRequests) -> Bool`; binding resolves only active published owned findings and actions resolve exact source/native ranges. Presentation accepts `marginVisible: Bool = false`; context visibility includes that flag. Rail accepts an optional open action and current selection flag. Workspace owns a transient explicit-open state, project-scoped and independent of source preparation.

- [x] Write failing whole-workspace access/focus/Undo/no-analysis tests using an injected paused counting backend, plus native duplicate/return/stale/marked/altered evidence navigation regressions.
- [x] Run focused suites and read genuine absence/behavior failures; retain RED logs.
- [x] Implement explicit rail/panel state and exact prepared navigation. Never fall back to generic quote search for quality insights. Reuse existing prepared UI, health/actions and exact source return.
- [ ] Run focused suites, build, full tests and PurloryBench with locked resolution and isolated user home. Review all four focus conditions inline; fix important findings with RED→GREEN coverage.
- [ ] Commit, publish/attach the bounded PR after predecessor main CI, inspect owner feedback, merge on exact-head all-three CI, synchronize clean primary main and verify merged-main CI. Record partial implementation and correct the earlier reachability claim on #126/#270/#158; keep acceptance/remaining producers open.

Inline plan review: existing rendering/production ownership and durable actions are reused; no duplicate analysis pipeline is added. Evidence/native mapping validation belongs in the existing action owner and is synchronous under the current stamp. Presentation flags only reserve geometry. All new behavior has named regression coverage, and current predecessor changes are immutable/verified before local successor work.
