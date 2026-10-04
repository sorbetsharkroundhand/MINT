# Temporary Source Search Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; no subagents.

**Goal:** Expose #108 original retrieval through model-free Command-K search.
**Architecture:** Runtime/query-fenced cancellable controller; native child panel;
existing ProjectEditorRequests native jump/return. No new project owner.
**Tech Stack:** Swift/Combine, AppKit, XCTest.
**Spec:** ../specs/2026-10-02-source-search-ui-design.md

## Global Constraints
- No LLM/network/model dependency, search history, actual manuscripts or CI waiting.
- Default Project scope; Here/Chapter follow #108 exactly; debounce 120ms.
- Preserve stable editor/undo and Hangul IME; standard opaque controls/system colors.
- Native panel width bounded by parent, minimum 360pt; results at most 100.

## Review Focus
- Late noncooperative results after newer query cannot publish (Task 1).
- Project/document/body changes including A→B→A invalidate scope (Task 1).
- Empty query and closed panel immediately cancel/clear work (Task 1).
- Search field marked text retains Return/Escape/arrows (Task 2).
- Native open/cancel/return and accessibility labels use real source routes (Task 2).

### Task 1: Scoped asynchronous controller
Files: create Workspace/SourceSearchController.swift and SourceSearchControllerTests.swift.
Produces SourceSearchInput and SourceSearchController(session:origin:cursor:delay:build:),
search(query:scope:), dismiss(), hits/isSearching/isInvalidated and change callbacks.
- [x] RED: newer query, real scopes, A→B→A/body changes, close and empty query.
- [x] Observe isolated test failure; implement cancellation handlers and ticket guards.
- [x] Focused/full tests, app/MINTBench builds; inline review, commit/push/attach Draft.

### Task 2: Native keyboard surface and return affordance
Files: create Workspace/SourceSearchPanel.swift and SourceSearchPanelTests.swift;
modify AppCommands.swift and ContentView.swift.
Consumes Task 1 controller and #108 native navigation requests.
- [ ] RED native open/close, keys/composition, result activation, ownership invalidation.
- [ ] Implement native panel, Command-K, source-return and visible stale status.
- [ ] Focused/full tests, app/bench builds, bundle and isolated launch/quit smoke.
- [ ] Inline whole-issue review, commit/push/attach Draft; owner checks stay pending.
