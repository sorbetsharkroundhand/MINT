# Manila Folder Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add persistent manuscript binders with manila tabs, reorder, tear-off and merge.
**Architecture:** Extend spatial slots; retain document-specific native hosts and use existing reversible drag transactions. Keep manuscript creation and selection in ProjectSession.
**Tech Stack:** Swift, AppKit, SwiftUI, XCTest; existing theme tokens only.
**Spec:** `docs/superpowers/specs/2026-10-25-manila-tabs-design.md`

## Global Constraints
- Work in the requested existing branch and preserve pre-existing edits; no unrelated commits.
- Tool tiles remain singletons; legacy layouts decode; document identities and content remain runtime-owned.
- Preserve focus, IME, scroll, cursor, undo and autosave. No network or model work.
- Review inline; final actual-app checks follow release policy.

## Review Focus
- Corrupt/duplicate tabs, deleted active document and last-tab protection.
- Same-binder reorder index adjustment and canceled split restoring dimensions.
- Switching a hidden tab restores the same editor and command target.
- Project switch during drag cannot restore old document IDs.
- Overflow tabs and controls remain reachable in narrow panes.

### Task 1: Persistent binders and controller transitions
- [x] Add failing tests for opening into a binder and selecting existing tabs.
- [x] Add `tabs`, legacy decoding, membership lookup, activation and normalized close/move behavior to SpatialWorkspaceLayout; add `.tab(anchor,index:)` drop targets.
- [x] Extend controller open/configure/close and reversible drag to preserve active binder selection and committed-only persistence.
- [x] Verify `swift test --filter SpatialBinderTests`; expected zero failures.

### Task 2: Native manila strip and stable editor presentation
- [x] Add native regression tests for retained editors, selection/scroll/undo and tab actions.
- [x] Add SpatialManilaTabBar.swift with scrolling, opaque fillet drawing, accessible tab/close/new/mode buttons and middle click.
- [x] Integrate the strip in SpatialDocumentTile; retain all open hosts, show only active slot members and dissolve body only over 0.12 seconds.
- [x] Verify `swift test --filter SpatialManila`; expected zero failures.

### Task 3: Drag integration and full verification
- [x] Add failing reorder/merge/tear-off/cancel/project isolation and native drag-routing tests.
- [x] Route native tab destinations before body-edge hit testing; preserve tool/navigator drag and existing drag pill.
- [x] Update existing split fixtures to explicitly split documents; retain their original assertions.
- [x] Run `swift build`, `swift test`, `swift build --product MINTBench`; review final diff and record results.

## Execution notes
- Implemented inline on the requested branch; retained existing uncommitted edits.
- Model/controller regressions, native editor retention, drag routing and first-reveal frame regressions were observed failing before their fixes.
- Scope decisions: retain the explicit spread-all command; tab reordering is presentation-only, while existing spatial/navigator reorder callbacks remain intact. Preserve the existing explicit chrome-hide preference.
- No commits or remote changes were made; this shared checkout contains unrelated ongoing work.
- Final build and test evidence, including baseline failures, is recorded in `docs/release/manila-tabs-verification-2026-10-25.md`.
