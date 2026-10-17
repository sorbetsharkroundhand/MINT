# Document Outline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task inline. Steps use checkbox (`- [ ]`) syntax for tracking. No subagents under the owner directive.

**Goal:** Expose General Outline with prepared model-free headings, exact native source navigation and current-section highlight.

**Architecture:** A cancellable Foundation projection and memoizing background actor feed one workspace-owned controller. Native navigation/current position reuse the existing captured row map; the UI occupies the existing dock while the editor stays mounted.

**Tech Stack:** Swift 6, macOS 14, Foundation, SwiftUI, AppKit, existing project/source/native-map types; no dependencies.

**Spec:** `docs/superpowers/specs/2026-10-17-document-outline-design.md`

## Global Constraints
- Owner-directed inline execution of UI/internal choices; written artifacts reviewed inline, not falsely labeled owner-reviewed.
- Existing editor remains mounted; no implicit manuscript edits, reorder, scene identity, network or LLM.
- Preserve original UTF-16 and source/native/runtime ownership, IME, Undo, focus, autosave and format/media/math round-trip.
- Preparation is background/cancellable, 350 ms debounce; foreground Ghost, serious/critical thermal state and Low Power Mode retire work.
- Keep two memoized document revisions; retained title/evidence prefixes <=256 UTF-16; scanner yields/checks cancellation every <=2,048 input UTF-16 units.
- Keep required CI unchanged. Actual app verification is owner-handled later; never launch local MINT/UI smoke.

## Review Focus
1. Identical duplicate/Unicode headings in different documents must never acquire another native editor's authority.
2. A giant single line/title or 300k document must remain cancellable; caret changes never rescan/hash/serialize source.
3. Queued A→B→A, metadata generations and stop/reentry must not publish stale headings or lose the latest snapshot.
4. Headings inside code/math, long scene segments and empty source must not invent navigable structure.
5. Dock/mode transitions and explicit jumps/returns must preserve native editor identity, selection, scroll and Undo; malformed/edited proof refuses.

### Task 1: Prepared source projection and owned background controller

**Files:** Create `Sources/MINTCore/Workspace/DocumentOutlineProjection.swift`, `Sources/MINTCore/Workspace/DocumentOutlineController.swift`, `Tests/MINTCoreTests/DocumentOutlineProjectionTests.swift`, `Tests/MINTCoreTests/DocumentOutlineControllerTests.swift`; expose the existing internal heading grammar in `Knowledge/DocumentOutline.swift` without changing scene parsing.

**Interfaces:** `DocumentOutlineProjection: Equatable, Sendable` provides `revision: String`, `headings: [Heading]`, `static build(_ source: String) async throws -> Self`, and `currentHeading(at sourceOffset: Int) -> Heading?`; `Heading` exposes `id: Int`/source offset, `level: Int`, `title: String`, bounded original `quote: String`, `sourceRange: Range<Int>`. `DocumentOutlineProjector` actor provides `project(_ snapshot: ProjectDocumentSnapshot) async throws -> DocumentOutlineProjection` and two-entry hash memoization. `PreparedDocumentOutline` pairs `identity` and `projection`. Main-actor `DocumentOutlineController` publishes `prepared`, `currentHeadingID`, `status`; exposes `update(_ snapshot: ProjectDocumentSnapshot?)`, `setForegroundBusy(_:)`, `setPolicyPaused(_:)`, `stop()`, `waitForCurrentWork()` and an injected async sleep/project function for deterministic tests. Status is idle/checking/paused/unavailable. Source captures remain immutable.

- [x] **Step 1: Write failing projection tests** for exact ordered duplicate heading offsets and source quotes with emoji/NFD/CRLF; fenced code/math exclusions; segment collapse; quiet empty source; bounded huge title; binary current-section lookup and cancellation. Write controller tests for same-body memoization, stale A→B→A/full generations, foreground/policy cancellation and stop/reentry.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'DocumentOutlineProjectionTests|DocumentOutlineControllerTests'`; expect missing projection/controller behavior. Preserve RED logs.
- [x] **Step 3: Implement** the stated projection/worker/controller interfaces. Share only the existing heading-line grammar, retain full scene-parser behavior. Source scan/hash executes on the background actor, with cooperative checks/yields and exact revision memoization; controller rechecks epoch/identity after every suspension.
- [x] **Step 4: Run** focused new suites plus `DocumentOutlineTests|WorkspaceShellModeTests|SourceNavigationTests`, then build/full tests/bench. Expect no failures. Review inline; publish the bounded foundation PR, attach it, merge only on all three exact-head CI successes, synchronize primary main and confirm merged-main CI before Task 2 delivery.
- [x] **Step 5: Commit** `feat: prepare owned model-free document outlines`. Record implementation separately from owner native acceptance.

### Task 2: Exact native navigation and visible General Outline

**Files:** Create `Sources/MINTCore/Editor/BlockTextView+DocumentOutline.swift`, `Sources/MINTCore/Workspace/DocumentOutlineView.swift`, `Tests/MINTCoreTests/DocumentOutlineNavigationTests.swift`; extend `Editor/SourceNavigation.swift`, `Project/ProjectSession.swift`, `Editor/BlockTextView.swift`, `Workspace/WorkspaceModePresentation.swift`, `Workspace/WorkspacePresentationState.swift`, `Workspace/WorkspaceLayoutPolicy.swift`, `Workspace/WorkspaceShellView.swift`, `ContentView.swift`; extend relevant workspace/layout/source-navigation tests.

**Interfaces:** Add `OutlineSourceTarget: Equatable, Sendable` carrying `identity`, `revision`, `evidence`, `level` and exact source offset, and `.heading(OutlineSourceTarget)` to `SourceNavigationIntent`. `ProjectEditorRequests.jump(to: Heading, prepared: PreparedDocumentOutline, in: ProjectSession) -> Bool` reuses source-return ownership. `BlockTextView.outlineSourcePosition(identity:) -> Int?` reads only the existing native row map; heading application checks native row source start/style/current mapped owner/revision. `WorkspacePresentationState` accepts `outlineVisible: Bool = false` and exposes context visibility independently of persisted tool IDs. General mode options are write/outline; Fiction remains write. The controller is owned once by WorkspaceSurface and preparation runs independently of panel appearance.

- [x] **Step 1: Write failing tests** for duplicate formatted headings with emoji/NFD and code/math neighbors; explicit heading jump + original selection/scroll/Undo return; edited target, wrong stable key, stale generation, marked text and NFC-vs-NFD refusal. Assert repeated current-position lookups do not increase serialization/reset counts. Pin General options, outline dock minimum-width reservation and restoration of persisted tools. Use hidden synthetic AppKit windows only.
- [x] **Step 2: Run** `swift test --disable-automatic-resolution --filter 'DocumentOutlineNavigationTests|SourceNavigationTests|WorkspaceShellModeTests|WorkspaceLayout'`; expect missing heading routes/panel visibility/current section.
- [x] **Step 3: Implement** exact mapped heading intents, source return UTF-16 guards and original-representation edit/synchronization guards, the logarithmic current-section lookup, prepared-only accessible panel, mode picker and existing-dock presentation. Connect snapshot/selection/foreground/energy lifecycle outside view-body calculations. Automatic results never move focus, reload editor or write preferences.
- [ ] **Step 4: Run** all outline/source/workspace/native projection suites, build/full tests/bench. Review inline and verify no extra hot-path source work or dependency/pin changes. Preserve required CI's package/smoke/archive jobs; no local product launch. Expect all three jobs green on PR and merged main.
- [ ] **Step 5: Commit** `feat: expose General outline with exact source navigation`, publish/attach bounded PR and merge on exact-head CI success. Sync primary main, record final implementation evidence on #271/#158, keep final native acceptance pending under #119.

## Inline plan review
The two tasks separate reusable prepared data ownership from native/UI integration. Task 2 consumes Task 1's exact Heading/prepared identities; source revision, quote budget and source offsets are the same across both. The five Review Focus conditions are assigned to named tests above. Preserve the owner-selected sequential inline method and standing merge authorization; do not ask again for UI/internal choices already delegated on 2026-10-17. Retain owner-only release/model decisions and final native acceptance as separate gates. Do not close #271 on a foundation-only merge.
