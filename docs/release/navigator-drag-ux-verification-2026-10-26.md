# Navigator drag UX investigation and verification

> Historical verification of an approach the user rejected. The Option-only grouping and dedicated extraction target below have been removed. See [legacy navigator parity verification](navigator-legacy-parity-verification-2026-10-26.md) for the current behavior and evidence.

Implemented inline on `codex/mint-editorial-redesign`. Preserved the existing dirty checkout, including the newer spatial drag engine, editor controls and navigator sort changes. No commits or remote changes were made.

## Findings and repair

1. Document-row centers previously resolved to `.inside(document)`, immediately creating a new folder. Ordinary drops now resolve to before/after positions; new-folder grouping requires Option at release. Entering a different existing folder requires dropping on that folder's central label area, not grazing its edges or one of its children.
2. Hit testing searched row bounds before establishing that the pointer was inside the navigator. An overflowing row could claim an outside drop. The resolver now checks the navigator boundary first. Native coverage also verifies that passing over a folder and releasing on a workspace document opens/merges it without changing its folder ownership.
3. Extraction relied on an unlabelled background or a blank row at the end of the scrollable list. A permanent labelled root target now sits outside the scroll view, above the footer. A direct document context-menu action also extracts a document to the root. Both use the existing durable transaction and undo path.
4. Alphabetical/date sorting could hide a successful reorder. A before/after drop now switches the navigator to manual order so the visible result matches the gesture.

The existing data transaction for grouping is retained. Manuscript bytes, folder identity and editor/drag ownership remain with their original components.

## Evidence

- New regressions were observed failing before their fixes for ordinary-drop grouping, missing visible extraction, folder-edge capture, outside-pane interception, and releasing Option before mouse-up. The fresh baseline also captured the manual-sort failure.
- Seven new native/hit-test cases cover those paths, nested extraction and undo, workspace opening after folder hover, and the fixed extraction target with more rows than fit in the viewport.
- Focused tests: **15 passed**, including existing navigation transactions and native editor-retention/reordering coverage.
- `swift build`: passed.
- `swift build --product MINTBench`: passed.
- Final complete `swift test`: **1,448 tests executed, 3 skipped, 33 assertion/error failures across 16 cases**, including 3 unexpected errors. The 16 failing cases exactly match the fresh pre-change baseline; there are no new failures. All 15 focused cases also passed inside the final suite. The pre-change suite included the new failing regressions; those failures are excluded when comparing existing cases. CI tests were not weakened or removed.
- An isolated native navigator render was inspected: the root drop target is visible above the footer and does not scroll away with the document rows.

Evidence is stored locally in `/tmp/mint-navigator-ux-evidence/`, including pre-change source snapshots, failing regression runs, a fresh pre-change full-suite log, focused/build logs and `navigator.png`. Native tests use synthetic projects with `CFFIXED_USER_HOME=/tmp/mint-navigator-ux-evidence/home`.

## Review

Inline review checked source/destination coordinate conversion, Option state at release, cross-folder boundaries, hidden/overflow rows, retained workspace routing, durable extraction/undo, and preference changes only after an accepted navigation transaction. The earlier grouping test's expected default was updated to reorder and an explicit grouping assertion was retained.

Actual-app physical mouse, IME and VoiceOver acceptance remain owner release checks. This verification does not claim a production-bundle or RC acceptance run.

## Existing whole-suite failures

The following cases failed both before and after this repair:

- `DocumentOutlineWorkspaceTests.testGeneralOutlinePanelKeepsEditorUndoAndSavedToolSelection`
- `FramedWorkspaceTests.testLongProjectTitleKeepsNavigatorCloseInsideCard`
- `FramedWorkspaceTests.testNavigatorColumnKeepsEditorAllocationAndIdentityAtNarrowWidths`
- `FramedWorkspaceTests.testNavigatorLocalCloseReturnsToEditor`
- `FramedWorkspaceTests.testPocketToolActionsPreserveCompositionAndToggleStoredTools`
- `FramedWorkspaceTests.testRailExposesFunctionalActionsAndSelectedNavigatorState`
- `FramedWorkspaceTests.testRailSearchHonorsMarkedTextAndEditability`
- `FramedWorkspaceTests.testRailToggleAndResizePreserveEditorAndPreferences`
- `FramedWorkspaceTests.testWindowTitleHitTestingReachesNativeDragRegion`
- `LivingMarginWorkspaceTests.testPreparedResultsNeverAutoOpenAndProjectSwitchRetiresExplicitOpening`
- `LivingMarginWorkspaceTests.testRailOpensAndClosesExistingPanelWithoutAnalysisOrEditorReplacement`
- `StoryMapShellTests.testActualFictionMapWorksWithAIOffAndKeepsEditorAcrossJumpReturnAndClose`
- `WorkspaceCommandPaletteTests.testTitleDoesNotSearchAndPouchOpensEmbeddedSearch`
- `WriterCompatibilityTests.testRailExposesAccessibleSearchAndCompatibilityMenuInGeneral`
- `WritingDiagnosticsEditorTests.testCorrectionIsOneUndoableEdit`
- `WritingEditorProjectionTests.testLoadAndNativeEditMapsMatchCanonicalSource`
