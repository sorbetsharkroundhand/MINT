# Living Margin Implementation Plan

> **Issue:** #105 — Build the Living Margin presentation framework
>
> **Contract:** `docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md`

## Goal

Add a shared, quiet intelligence surface for General and Fiction writing without introducing inference, analysis, or durable derived state. Insights must remain evidence-first, dismissible, stable at 0/1/5/20 items, and must not steal editor focus when the surface is shown or hidden.

## Architecture

- Put the cross-layer `EvidenceAnchor` contract in `Knowledge/`, implemented with the existing `SourceAnchor` re-anchoring utility.
- Put provider-independent Living Margin data, filtering, ordering, deduplication, and transient dismissal state in a new `Intelligence/` package area.
- Keep the SwiftUI view a renderer/consumer only. It receives actions through callbacks and never invokes MLX, scans the manuscript, or performs writing-quality analysis.
- Expose General/Fiction renderer policies at the presentation boundary so General Writing never depends on Fiction domain types.
- Integrate the surface into the existing dockable writing-tool area and bridge evidence jumps to legacy entries by their preserved document UUID.

## Task 1: Evidence and insight contracts

**Files**

- Create `Sources/MINTCore/Knowledge/EvidenceAnchor.swift`
- Create `Sources/MINTCore/Intelligence/MarginInsight.swift`
- Create `Tests/MINTCoreTests/EvidenceAnchorTests.swift`
- Create `Tests/MINTCoreTests/MarginInsightTests.swift`

**Steps**

1. Add failing tests for exact, resilient, UTF-16 hint, and stale evidence resolution.
2. Implement `EvidenceAnchor(documentID:sceneHash:quote:utf16Hint:)` as a Codable/Hashable/Sendable value. Resolve quoted evidence only through `SourceAnchor.resilientQuery`; a UTF-16 hint must never make stale evidence jumpable.
3. Add failing contract tests for all six insight kinds and stable action identity.
4. Implement `MarginInsight` and value-based `MarginAction` contracts with public initializers.
5. Run the focused tests.

## Task 2: Presentation policy and transient state

**Files**

- Create `Sources/MINTCore/Intelligence/LivingMarginModel.swift`
- Create `Tests/MINTCoreTests/LivingMarginModelTests.swift`

**Steps**

1. Add failing tests for deterministic priority ordering, ID/content deduplication, quiet low-confidence suppression, General/Fiction kind boundaries, dismissal, replacement publication, and stable 0/1/5/20 results.
2. Implement a pure `LivingMarginPolicy` with explicit mode capability rules and stable ordering.
3. Implement an `@MainActor` observable model whose insight and dismissal state is presentation-only and resettable. Publication must be synchronous and must perform no I/O.
4. Run the focused tests and refactor only after they pass.

## Task 3: Quiet, accessible Living Margin view

**Files**

- Create `Sources/MINTCore/Intelligence/LivingMarginView.swift`
- Create `Tests/MINTCoreTests/LivingMarginAccessibilityTests.swift`

**Steps**

1. Add testable presentation descriptors for labels, confirmation language, action labels, and mode-specific rendering.
2. Build a flat typographic list with restrained separators, a quiet empty state, evidence jump actions, optional secondary actions, and dismissal controls.
3. Use lazy rendering for bounded 20-item presentation, combine each insight into a useful VoiceOver element, and expose named accessibility actions.
4. Respect Reduce Transparency in the transient surface and Reduce Motion in reveal/dismiss transitions.
5. Run the focused tests.

## Task 4: Workspace integration and focus-safe behavior

**Files**

- Modify `Sources/MINTCore/SidebarView.swift`
- Modify `Sources/MINTCore/Workspace/WorkspaceShellView.swift`
- Modify `Sources/MINTCore/ContentView.swift`
- Modify `Sources/MINT/MINTApp.swift`
- Modify/add `Tests/MINTCoreTests/WorkspaceShellModeTests.swift`

**Steps**

1. Add a Living Margin tool section available in both writing modes and inject one app-lifetime `LivingMarginModel` through `ContentView` into `WorkspaceSurface`.
2. Render Living Margin in the existing dockable tool surface while retaining the placement menu and close control.
3. Bridge evidence jumps to `EntryStore` only when `EvidenceAnchor.documentID` resolves to a legacy entry ID and `resolvedQuery(in:)` succeeds. Request editor focus only for an explicit evidence jump, not for showing or hiding the margin.
4. Add regression coverage showing section visibility changes do not emit editor focus requests and mode policy remains correct.

## Task 5: Verification and delivery

1. Run `swift test`.
2. Run `swift build` and `swift build --product MINTBench`.
3. Run `scripts/build-mint-app.sh`, `scripts/smoke-mint-app.sh`, and `scripts/ui-smoke-mint-app.sh` when the desktop session permits accessibility automation.
4. Review the diff against issue #105 and the approved design contract.
5. Commit, push `codex/105-living-margin`, and open a PR linked to #105. Do not close the issue before merge and CI/E2E evidence.
