# Framed Workspace and Navigation Rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The owner selected inline execution without subagents in #163.

**Status:** Approved by the owner on 2026-10-11 for sequential inline implementation.

**Goal:** Ship an opaque manuscript frame, adaptive navigator card, and functional persistent navigation rail while retaining the existing editor and writer data.

**Architecture:** Existing preference bindings feed an immutable presentation snapshot and a pure geometry policy. The shell keeps the editor and visible navigator in stable structural slots; the rail reuses existing actions. Project/runtime ownership remains in `ProjectSession`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, macOS 14+, existing MINT theme/tokens; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-11-framed-workspace-design.md` — approved 2026-10-11.

**Scope authority:** #163 normally starts after a stable first release. The owner's current request and approved frame/rail design advance this selected post-release work while #99/#119 and the model/Store gates remain open; this is not evidence that those release gates passed.

## Global Constraints

- Rail width is 56 points, outer inset and surface gaps are 10 points, and frame corner radius uses `MintRadius.lg` (12 points).
- Reserve a 52-point shared window-chrome row; use the measured traffic-light safe region. Buttons have at least a 32-by-32-point hit area.
- Preserve an opaque manuscript, one material layer at most, Pretendard UI, Noto Serif KR manuscript, approved mint accent, and custom palettes.
- Navigator width defaults to 250 with existing 200–360 limits; retain drag resistance and collapse hysteresis at 150/176 points. Manuscript minimum is 560 points.
- Below 1,024 points, navigator overlays; otherwise it is inline when the width budget permits. Bottom/floating height limits remain 320/520 points.
- Retain `mint.sidebarVisible`, `mint.sidebarWidth`, `mint.sidebarSection`, `mint.toolDockPosition`, and `mint.chromeHidden`; derived layout never writes preferences.
- No model selection, manuscript migration, dependency changes, NSToolbar migration, new AI destinations, focus-mode expansion, or automatic quieting.
- Preserve editor identity, caret/selection, marked text, undo, source return, Ghost semantics, and General/AI-disabled writing.
- Execute inline without subagents. English repository prose/comments; Korean UI and fixtures are permitted.
- Every PR stays approximately 500 changed lines or fewer and main stays buildable. Never weaken CI or mark #163/#119 fully accepted from unit tests.
- Use `--disable-automatic-resolution` for local Swift commands; run Swift builds/tests sequentially. Preserve the existing worktree's ignored bundles and model-validation cache.

## Review Focus

1. Saved `timeline`, unknown tool IDs, and non-finite widths must not be silently rewritten at startup (Tasks 1–2).
2. Resizing through 1,023/1,024 while editing or renaming must preserve the same native views and pending input (Task 3).
3. A long project title and measured window buttons must fit without overlap; frame decoration must leave editor transients visible (Tasks 3 and 5).
4. Search requested while the navigator is hidden must focus its field once; a later ordinary reopen must preserve manuscript focus (Task 4).
5. Repeated resize, collapse, and tool fallback must restore saved placement without changing writer data or undo (Tasks 2–5).

## File and PR Map

- Preparation PR: approved spec and this reviewed plan, separately from implementation to preserve the review budget.
- PR 1 / Task 1: presentation snapshot and saved-choice preservation; native test harness.
- PR 2 / Task 2: layout policy, complete width accounting, and geometry regressions.
- PR 3 / Task 3: framed shell, adaptive navigator, native chrome and identity tests.
- PR 4 / Task 4: functional rail, toolbar simplification, and keyboard/action regressions.
- Task 5: one integrated app verification batch after all four implementation slices.

Use a bounded child issue for each implementation PR, linked to #163, with its current acceptance contract. Keep the parent open. Refresh main and that child's body/comments/active PR before coding it. Branch from the merged predecessor using `codex/163-<slice>`. PR summaries link the child without claiming the entire epic is complete.

Local test commands below use a unique synthetic home via `CFFIXED_USER_HOME` for the test process, created under this worktree's ignored `build/` directory. Do not change `HOME`, touch real manuscripts, or run local app launch scripts until Task 5. Native XCTest fixtures may create and close their own synthetic windows.

---

### Task 1: Preserve saved presentation choices

**Files:** Create `Sources/MINTCore/Workspace/WorkspacePresentationState.swift`, `Tests/MINTCoreTests/WorkspacePresentationTests.swift`, and `Tests/MINTCoreTests/FramedWorkspaceTests.swift`; modify `Sources/MINTCore/Workspace/WorkspaceShellView.swift` (`WorkspaceSurface`).

**Interfaces:** Produce `WorkspacePresentationState.init(navigatorVisible: Bool, navigatorWidth: Double, rawToolSection: String, rawToolDock: String, chromeHidden: Bool)` with immutable inputs, `toolSection: SidebarSection?`, and `toolDock: ToolDockPosition`. `toolSection` permits only `.bible`, `.narrative` (raw `timeline`), and `.context`; other values return nil. Invalid dock strings resolve to `.automatic`. This type performs no I/O or preference writes.

Produce test-only `FramedWorkspaceHarness.init(width: CGFloat = 1180, presentationDefaults: [String: Any] = [:], appearance: ColorScheme = .light, reduceMotion: Bool = false, reduceTransparency: Bool = false) async throws`, `layout() async`, `editor() async throws -> BlockTextView`, `elements() -> [any NSAccessibilityProtocol]`, and `close()`. Expose `fixture`, `requests`, `window`, and `host`. Reuse `LegacyBoundaryFixture` and `LegacyUndoWindow`; seed preferences before hosting `ContentView`, disable autocomplete in its fixture settings, and apply `.defaultAppStorage(fixture.defaults)` plus the requested environments. Follow `SourceNavigationHarness` cleanup and bounded layout-yield pattern; deduplicate accessibility nodes by object identity before counting controls.

- [ ] **Step 1 — Write native regressions against the existing workspace.** `testSavedToolChoiceSurvivesWorkspaceAppearance` seeds each of `bible`, `timeline`, and `context`, verifies the stored raw string survives layout and the matching tool title is visible. `testUnknownAndDeferredToolChoicesRemainStoredAndQuiet` seeds `margin` and `unknown`, verifies bytes/preferences remain unchanged and no active tool is shown. In both, compare the active project and selected document before/after.
- [ ] **Step 2 — Run RED.** `swift test --disable-automatic-resolution --filter FramedWorkspaceTests`. Expected runtime failure: the current `.onAppear` rewrites the seeded raw section to `files`. Record the exact failing assertions before introducing the new snapshot API.
- [ ] **Step 3 — Add snapshot coverage.** `testSnapshotValidatesToolsAndDockWithoutMutatingInputs` asserts the allowed sections above, nil for `files`/`margin`/`unknown`, `.left` for raw `left`, and `.automatic` for an invalid dock; preserve raw strings, bools, and width. Expected missing-type failure until Step 4.
- [ ] **Step 4 — Implement the snapshot and integrate it.** Keep the five existing preference bindings in their current owners, adding `mint.chromeHidden` to the surface's snapshot input. Use validated selection/dock for visible tool composition. Remove only the unconditional startup section reset. Keep callbacks and runtime ownership intact.
- [ ] **Step 5 — Verify GREEN.** `swift test --disable-automatic-resolution --filter 'WorkspacePresentationTests|FramedWorkspaceTests|WorkspaceShellModeTests|WriterCompatibilityTests'`. Expected all assertions pass; existing General writer-data access stays green. Then run the per-PR delivery checks below.
- [ ] **Step 6 — Commit and deliver PR 1.** Commit only the named source/tests with `feat: preserve workspace presentation preferences`; merge under the per-PR gate before starting Task 2.

### Task 2: Resolve the complete framed width budget

**Files:** Create `Sources/MINTCore/Workspace/WorkspaceLayoutPolicy.swift`; modify `Sources/MINTCore/Workspace/WorkspaceShellView.swift` and `Tests/MINTCoreTests/WorkspaceLayoutTests.swift`.

**Interfaces:** Move `ToolDockPosition`, `WorkspaceToolbarDensity`, and `WorkspaceLayoutState` to the policy file without changing existing callers. Keep `WorkspaceMotion` with presentation, outside the pure geometry layer.

Produce `WorkspaceNavigatorPlacement: Equatable` (`hidden`, `inline`, `overlay`), immutable `WorkspaceResolvedLayout` (`navigatorPlacement`, `navigatorWidth`, `navigatorMaximumWidth`, `navigatorReservation`, `toolDock`, `manuscriptWidth`), and `WorkspaceLayoutPolicy.resolve(availableWidth: CGFloat, presentation: WorkspacePresentationState, railWidth: CGFloat = 56, projectedNavigatorWidth: CGFloat? = nil) -> WorkspaceResolvedLayout`. Geometry values use `CGFloat`; `toolDock` uses `ToolDockPosition`. Constants: `outerInset = 10`, `surfaceGap = 10`, `railWidth = 56`, `chromeHeight = 52`, `overlayThreshold = 1024`, `toolSeparatorWidth = 1`.

Width budget: subtract both outer insets and, when nonzero, rail width plus one gap. Inline navigator reserves its width plus one gap; overlay/hidden reserves zero. Side tool inside the writing area costs 340 plus its 1-point separator, only when a validated tool is visible. Apply the existing drag projection/resistance before clamping; overlay width does not reserve 560 points beside itself. Side placement must leave at least 560 points for the actual manuscript. Resolve no negative/non-finite frame dimensions and preserve persisted inputs.

- [ ] **Step 1 — Add the existing-helper regression first.** `testSideFitIncludesRenderedDivider` asserts automatic/left/right fallback to bottom at 1,150 with visible 250-point navigator and fit at 1,151. With hidden navigator the corresponding boundary is 900/901.
- [ ] **Step 2 — Run RED before referencing new types.** `swift test --disable-automatic-resolution --filter WorkspaceLayoutTests`. Expected runtime failure: old helper permits the side dock one point too early.
- [ ] **Step 3 — Add resolved-layout regressions.** For saved width 250, no active tool, rail 56, assert the following exact matrix:

| Workspace width | Navigator | Reserved width | Manuscript width |
| ---: | --- | ---: | ---: |
| 860 | overlay | 0 | 774 |
| 1023 | overlay | 0 | 937 |
| 1024 | inline | 260 | 678 |
| 1180 | inline | 260 | 834 |
| 1440 | inline | 260 | 1094 |

`testFramedSideFitUsesAllAllocatedGeometry` uses a valid `bible` tool: automatic/left/right fall back at 1,246 and fit at 1,247 with inline 250 navigator; actual manuscript width at fit is 560. Overlay/hidden navigator boundary is 986/987. Assert side choices restore after widening, explicit bottom/floating remain explicit, and `files`/unknown reserve no tool width. `testProjectionKeepsResistanceAndSafeWidths` covers saved -10, infinity, NaN, >360, drag 175/150, and a zero initial viewport; outputs stay finite/nonnegative and existing hysteresis tests remain unchanged.
- [ ] **Step 4 — Implement policy and extraction.** Correct the old helper's separator budget, share the width/resistance rules, and retain existing helper semantics for current callers. The new framed resolver becomes active in Task 3; do not pre-emptively redesign the shell here.
- [ ] **Step 5 — Verify GREEN.** `swift test --disable-automatic-resolution --filter 'WorkspaceLayoutTests|WorkspacePresentationTests|FramedWorkspaceTests'`, then per-PR checks. Expected existing and new geometry tests pass.
- [ ] **Step 6 — Commit and deliver PR 2.** `refactor: centralize complete workspace layout geometry`; proceed only after its gate.

### Task 3: Render the framed shell without replacing the editor

**Files:** Create `Sources/MINTCore/Workspace/WorkspaceFrame.swift`; modify `Sources/MINTCore/Workspace/WorkspaceShellView.swift`, `Sources/MINTCore/Workspace/ProjectNavigatorView.swift`, `Sources/MINTCore/ContentView.swift` (`EditorToolbar` padding), `Tests/MINTCoreTests/FramedWorkspaceTests.swift`, and `Tests/MINTCoreTests/WindowChromeGeometryTests.swift`.

**Interfaces:** Produce `WorkspaceFrame<Content: View>.init(theme: MintTheme, @ViewBuilder content: () -> Content)` and `WorkspaceWindowChrome.init(projectTitle: String, theme: MintTheme)`. Frame uses opaque surface, 12-point rounded border, and identifier `mint.workspace.frame`; its decoration cannot clip the editor's transient controls. Chrome uses `WindowChromeProbe`/`WindowChromeGeometry`, a native `NSView` drag region (`mouseDownCanMoveWindow == true`), and title identifier `mint.workspace.chrome.title`. No custom drag tracking or window style mutation.

Change shell composition to consume `presentation: WorkspacePresentationState`, its existing width binding/collapse callback, plus `railWidth: CGFloat` and a view-builder `rail` slot. `WorkspaceSurface` supplies zero rail width and `EmptyView` in this intermediate PR; existing toolbar entry points remain usable and no empty rail is displayed. Task 4 supplies the real rail and width 56. Both use the same composition/policy.

Add `onClose: () -> Void` to `ProjectNavigatorView`; connect it to the existing collapse/focus callback. Provide a local accessible close action so an overlay has a pointer/keyboard exit even before rail integration. Header leading padding becomes 12 rather than 74. Add `mint.navigator.search` and `mint.navigator.rename` identifiers to active fields. Document toolbar uses symmetric existing 22-point padding because window controls now belong to the separate chrome row.

- [ ] **Step 1 — Write native frame and adaptation regressions.** `testFrameAndWindowTitleHaveSeparateSafeGeometry` requires the new frame identifier, an opaque surface, a 52-point chrome row, and project title beyond measured window controls plus the existing 12-point traffic-light gap; include a long project title. `testNavigatorOverlayKeepsEditorAllocationAtNarrowWidths` compares width 860/1023 versus 1024/1180/1440, using rail width zero for this intermediate shell and policy expectations from Task 2. Require local close/reopen and unchanged preferences.
- [ ] **Step 2 — Run RED.** `swift test --disable-automatic-resolution --filter FramedWorkspaceTests`. Expected missing frame/close identifiers and original inline navigator allocation at narrow widths. Do not launch the app to obtain this failure.
- [ ] **Step 3 — Add safety regressions.** `testResizePreservesEditorSelectionUndoAndMarkedText` groups one native edit, snapshots editor identity/document key/selection/undo manager, resizes repeatedly, and verifies the same instance and undoable text; a second case sets marked text `한` and requires unchanged composition/selection until explicit cleanup. `testResizePreservesNavigatorSearchAndPendingRename` captures native field identity and text, crosses 1023/1024 both ways, and verifies no premature rename commit. `testFrameSupportsDisplayAccessibilityOptions` hosts light/dark/custom themes with Reduce Motion/Transparency and verifies the same layout state, opaque paper, accessible close, and focus/undo survival.
- [ ] **Step 4 — Implement stable composition.** Keep one unconditional editor slot. Allocate inline navigator space separately and place the visible navigator in one stable overlay slot whose position changes with resolved layout; do not build separate navigator/editor branches for inline versus overlay. Anchor overlay to the manuscript's leading edge, accounting for an effective left tool. Use policy dimensions for divider bounds and dock fit. Reuse existing Reduce Motion-aware transitions and preserve no-tool/floating paths. Add frames/chrome and local navigator close, with solid card surfaces rather than stacked material.
- [ ] **Step 5 — Verify GREEN.** `swift test --disable-automatic-resolution --filter 'FramedWorkspaceTests|WindowChromeGeometryTests|WorkspaceLayoutTests|SourceNavigationTests|SourceSearchPanelTests|MathEditGeometryTests'`, then per-PR checks. Any pre-existing baseline failure must be diagnosed separately, not fixed by weakening the new assertions.
- [ ] **Step 6 — Commit and deliver PR 3.** `feat: frame the manuscript and adapt navigator presentation`. If changes exceed the review budget, split chrome/frame decoration and navigator adaptation into two buildable commits/PRs, with their own focused RED/GREEN cycle; retain the exact acceptance above.

### Task 4: Connect the functional navigation rail

**Files:** Create `Sources/MINTCore/Workspace/WorkspaceRail.swift`; modify `Sources/MINTCore/Workspace/WorkspaceShellView.swift`, `Sources/MINTCore/Workspace/ProjectNavigatorView.swift` (transient search requests), `Sources/MINTCore/ContentView.swift` (`EditorToolbar`), `Tests/MINTCoreTests/WriterCompatibilityTests.swift`, `Tests/MINTCoreTests/FramedWorkspaceTests.swift`, and `scripts/ui-smoke-mint-app.sh` (additional assertions only).

**Interfaces:** Produce `WorkspaceRail.init(navigatorVisible: Binding<Bool>, section: Binding<String>, session: ProjectSession, requests: ProjectEditorRequests, theme: MintTheme, openSettings: @escaping () -> Void)`. Files is a native control that preserves pointer-click editor focus, with identifier `mint.workspace.navigator-toggle`, show/hide label, and selected state. Rail identifier is `mint.workspace.rail`; Settings is `mint.workspace.settings`. Search and saved-information controls retain their existing identifiers/actions and become at least 32-by-32. Use the standard `openSettings` environment action supplied by the surface.

Add internal `ProjectEditorRequests.consumeSearchFocusRequest() -> Bool`, backed only by a private transient consumed sequence. `focusSearch()` remains unchanged publicly. Navigator consumes a pending request on appearance and on request changes; a previously consumed request cannot focus a later ordinary reopen. This adds no persistent preference or domain state.

- [ ] **Step 1 — Write native rail regressions.** `testRailExposesFunctionalActionsAndSelectedNavigatorState` requires one accessible rail, four functional entries, 32-point hit areas, correct file-toggle label/state, and no deferred AI destinations. `testRailToggleAndResizePreserveEditorAndPreferences` toggles repeatedly and resizes 860/1180/1440 while comparing the same editor/document key, selection, first responder, undo manager, manuscript, and saved width/dock; final width expectations now include rail 56.
- [ ] **Step 2 — Run RED.** `swift test --disable-automatic-resolution --filter FramedWorkspaceTests`. Expected missing rail identifiers/controls and final 56-point geometry.
- [ ] **Step 3 — Pin keyboard and saved-data routes.** `testHiddenNavigatorSearchRequestIsConsumedOnce` starts hidden, sets visibility plus `focusSearch()`, verifies the navigator's field editor receives focus, then closes/reopens without another request and verifies manuscript focus survives. `testRailSearchHonorsMarkedTextAndEditability` verifies marked manuscript blocks opening search without changing composition and noneditable project disables search. Migrate the existing `WriterCompatibilityTests.testToolbarExposesAccessibleSearchAndCompatibilityMenuInGeneral` to inspect the real workspace rail; retain all menu labels, native keyboard focus, raw preference changes, selection/project equality, and search-close/source-return checks. Keep the second General writer-fields test unchanged. Add `testDocumentToolbarRetainsLocalControlsWithoutDuplicateGlobalActions` for title/model/notice retention and absence of duplicate rail actions.
- [ ] **Step 4 — Implement rail and remove duplicate toolbar actions.** Supply rail width 56, standard Settings callback, and existing search/menu actions from the surface. Remove only sidebar/search/compatibility/Settings controls and their unused state from the document toolbar. Keep source request routing, document modes, long-paragraph notice, model status, and focus-mode behavior. Add one-time transient search-request consumption. Add `ui present "mint.workspace.frame"` and `ui present "mint.workspace.rail"` to the existing UI smoke's writing phase; retain all manuscript, writer-data, recovery, and reopen assertions.
- [ ] **Step 5 — Verify GREEN.** `swift test --disable-automatic-resolution --filter 'FramedWorkspaceTests|WriterCompatibilityTests|WorkspaceLayoutTests|WorkspaceShellModeTests|SourceSearchPanelTests|SourceNavigationTests'` and `sh -n scripts/ui-smoke-mint-app.sh`, then per-PR checks. Actual script launch remains Task 5.
- [ ] **Step 6 — Commit and deliver PR 4.** `feat: move workspace navigation into a persistent rail`. Split rail installation and toolbar/request cleanup only if necessary for the review budget; an intermediate version must retain functional routes and no dead controls.

## Per-PR Delivery Gate

1. Record focused RED/GREEN evidence for the actual code change; inspect the full diff and confirm no manuscript/runtime ownership moved.
2. Run sequentially: `swift build --disable-automatic-resolution`, `swift test --disable-automatic-resolution`, and `swift build --disable-automatic-resolution --product MINTBench`. Expected exit 0, no new failing tests, and no lockfile changes. Run only relevant focused reruns after new edits/failures.
3. Create an English PR with its exact scope and verification evidence; attach every created PR to this chat. Use `Refs #child` rather than automatic closing syntax until any required native batch/manual acceptance is satisfied. Do not launch local app smoke per PR. Preparation docs require diff/link validation, not a redundant local test suite.
4. Require all three CI jobs: `MINT / Debug Build & Test`, `App / Release Bundle & Smoke`, `App / Unsigned Xcode Archive`. Existing CI launches/sandbox/archive checks remain intact. Address actionable feedback or failures before merging; otherwise merge immediately after success under existing owner authorization.
5. Verify merge/main CI, refresh the worktree from main for the next slice, and close only the bounded child after its required evidence. Keep broad #163 and owner acceptance gates open.

### Task 5: One integrated native verification batch

**Files:** Existing `scripts/build-mint-app.sh`, `scripts/smoke-mint-app.sh`, and `scripts/ui-smoke-mint-app.sh`; evidence on the #163 children and #119. No new product behavior is planned in this task.

- [ ] **Step 1 — Freeze a clean merged source and preserve artifacts.** Confirm all implementation slices and required CI merged. Record commit/tree identity. Because bundle construction overwrites `build/MINT.app`, first preserve the existing bundle at a unique source-tagged path and verify its binary hash; retain the old ZIP and isolated model-validation directory untouched.
- [ ] **Step 2 — Build and run the existing isolated scripts once.** `scripts/build-mint-app.sh`, `scripts/smoke-mint-app.sh`, then `scripts/ui-smoke-mint-app.sh`. Expected clean launch/termination and every editor, writer-data, recovery, frame/rail, resize, and reopen assertion passes. Preserve exact failures and diagnose them; do not call an assisted/retried run an unassisted pass.
- [ ] **Step 3 — Verify the new UI matrix in the same batch.** Synthetic projects only, isolated with `CFFIXED_USER_HOME`: 860/1180/1440 widths, light/dark/custom palette, Reduce Motion/Transparency, native window controls/dragging/full screen, keyboard rail and menu reopen/search, navigator close, source return, focus-mode menu, field rename across resize, and frame/transient visibility. Record what automation actually verifies.
- [ ] **Step 4 — Keep manual acceptance honest.** Real Hangul IME, VoiceOver, Ghost Tab/right-arrow/Esc, and final visual quality require their actual evidence. Leave unperformed owner checks open and link exact artifacts/results rather than claiming inferred acceptance. Model selection and Store distribution remain deferred.
- [ ] **Step 5 — Publish scoped evidence and finish this selected outcome.** Update the bounded children/#163 with integrated results and remaining manual checks; keep later morphing/focus/utility/Intelligence work explicit. No telemetry, public submission, or real-manuscript mutation.

## Plan Self-Review

- All approved visible structure, rail routes, preference preservation, geometry, view identity, accessibility, and verification requirements map to Tasks 1–5.
- Interface names and types above are the same producers/consumers throughout; UI tests exercise the real workspace rather than a parallel fake layout.
- The five Review Focus conditions have named regression tests or explicit integrated checks in their owning tasks.
- Preparation docs are separated from product changes to preserve the approximately 500-line PR budget.
- Scope remains frame/rail plus required support; broader #163 features and final owner gates are not claimed complete.
- Implementation starts only after the owner reviews this plan. Preserve the already selected inline execution method.
