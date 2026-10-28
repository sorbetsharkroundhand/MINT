> Historical evidence: the names below identify the original tested artifacts, before the Purlory rename.

# Manila folder tabs verification — 2026-10-25

## Scope and checkout

Implemented on `codex/mint-editorial-redesign`. Existing uncommitted changes were preserved. No commits, pushes, issue changes, or merges were performed.

Document slots now retain ordered tabs and an active tile, with backward-compatible decoding. Native paper tabs support selection, hover/middle-click close, new documents, writing modes, quiet typing, horizontal overflow, reorder, tear-off and merge. Document-specific editor hosts remain alive for open tabs. Tool headers and the existing column/row engine remain in place.

## Automated evidence

- `swift build`: passed.
- `swift build --product MINTBench`: passed.
- Focused model, controller, native tab/drag/editor, source navigation and calm-writing regressions: 57 tests passed, zero failures.
- Final complete `swift test`: 1,427 tests executed, 3 skipped, 46 assertion/error failures across 19 test cases (3 unexpected errors). All 19 failing cases also failed in the comparison without tab changes; no additional failing cases were observed. The 57 focused tests passed again inside this final whole-suite run. Existing failures are not treated as passing or removed from CI.
- Native test processes used `CFFIXED_USER_HOME=/tmp/mint-manila-evidence/home` and synthetic projects with isolated preferences.
- Native narrow-strip renders in light and dark were inspected. These are test-view renders, not real-app acceptance or Store distribution evidence.

Regression coverage includes legacy slot decoding; tab order and active-tab round-trip; invalid/deleted/duplicate tabs; current-binder opening; selecting existing hidden tabs; last-tab protection; native controls; middle-click close; narrow overflow; retained editor/undo/selection/scroll; stationary first reveal with motion enabled; drag reorder/split/merge; cancellation without persistence; and stale drag invalidation on project switch or trash changes.

## Baseline comparison

To distinguish this feature from ongoing workspace work, a separate temporary source copy was prepared without the manila-tab implementation. It restored the original layout, controller and canvas behavior while retaining the pre-existing navigator integration and document status changes. The user's checkout and branch were never reset or switched. The same test environment reproduced all 19 failing test cases from the initial whole-suite run (46 assertions/errors, including 3 unexpected errors).

Failing cases reproduced without the tab changes:

- `DocumentOutlineWorkspaceTests.testGeneralOutlinePanelKeepsEditorUndoAndSavedToolSelection`
- `FramedWorkspaceTests.testLongProjectTitleKeepsNavigatorCloseInsideCard`
- `FramedWorkspaceTests.testNavigatorColumnKeepsEditorAllocationAndIdentityAtNarrowWidths`
- `FramedWorkspaceTests.testNavigatorLocalCloseReturnsToEditor`
- `FramedWorkspaceTests.testPocketToolActionsPreserveCompositionAndToggleStoredTools`
- `FramedWorkspaceTests.testRailExposesFunctionalActionsAndSelectedNavigatorState`
- `FramedWorkspaceTests.testRailSearchHonorsMarkedTextAndEditability`
- `FramedWorkspaceTests.testRailToggleAndResizePreserveEditorAndPreferences`
- `FramedWorkspaceTests.testWindowTitleHitTestingReachesNativeDragRegion`
- `HTMLWorkspaceFidelityTests.testFixedPouchKeepsControlsSeparateFromDocumentFormatting`
- `HTMLWorkspaceFidelityTests.testSecondaryMenuKeepsModesAndAIStateAccessible`
- `HTMLWorkspaceFidelityTests.testSpatialSelectionRestoresFormattingToolbarAndPreservesEditorFocus`
- `LivingMarginWorkspaceTests.testPreparedResultsNeverAutoOpenAndProjectSwitchRetiresExplicitOpening`
- `LivingMarginWorkspaceTests.testRailOpensAndClosesExistingPanelWithoutAnalysisOrEditorReplacement`
- `StoryMapShellTests.testActualFictionMapWorksWithAIOffAndKeepsEditorAcrossJumpReturnAndClose`
- `WorkspaceCommandPaletteTests.testTitleDoesNotSearchAndPouchOpensEmbeddedSearch`
- `WriterCompatibilityTests.testRailExposesAccessibleSearchAndCompatibilityMenuInGeneral`
- `WritingDiagnosticsEditorTests.testCorrectionIsOneUndoableEdit`
- `WritingEditorProjectionTests.testLoadAndNativeEditMapsMatchCanonicalSource`

These failures cover existing navigator/rail geometry and action expectations, SwiftUI tool accessibility/sheet expectations, and editor diagnostic/projection expectations. Their tests and unrelated implementations were not weakened or rewritten for this feature.

## Review and remaining acceptance

Inline review checked slot membership and normalization, same-binder insertion indices, source/destination retention during drag, active-neighbor selection on close, project-scoped persistence, hidden native editor identity, and motion/overflow behavior. It found and fixed a zero-sized first-reveal animation and resurrection of trashed tabs from a pending drag. Review was performed inline under the repository's release execution policy.

The explicit spread-all command remains available. Tab-strip reordering changes presentation only; existing spatial/navigator reorder callbacks retain their previous behavior. The explicit chrome-hide preference still hides tab chrome.

Actual-app visual acceptance, physical Hangul IME, VoiceOver and live Ghost keyboard checks remain owner checks under `docs/release/verification-and-support.md`. No app bundle was launched or shipping model selected. This is not a merge-ready/RC claim while the existing whole-suite failures remain.

Local detailed logs and test renders: `/tmp/mint-manila-evidence/`.

The subsequent connected-tab, document-list return and complex-math changes are recorded in [the follow-up verification](binder-drop-math-verification-2026-10-26.md).
