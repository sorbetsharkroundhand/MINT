# Deterministic Source Search Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; no subagents.

**Goal:** Deliver scoped original passages and safe source jump/return for #108.
**Architecture:** Pure retrieval over project snapshots; editor-owned native
navigation requests remain separate from durable session state.
**Tech Stack:** Swift/Foundation, AppKit/TextKit, XCTest.
**Spec:** ../specs/2026-10-02-source-search-design.md

## Global Constraints
- No model/network/disk search, derived evidence, owner checkboxes or CI waiting.
- Preserve project ownership, Hangul IME, stable editor identity and undo.
- Here = current scene; Chapter = contiguous prefix-two heading group; Project = visible documents.
- Before-cursor search clips original source before matching; output limit 100.
- Keep each pushed Draft slice around 500 changed lines, reuse managed workspace.

## Review Focus
- Duplicate/edited quotes resolve uniquely or remain stale (Task 1).
- UTF-16 emoji/Hangul and cursor-split matches never leak future text (Task 1).
- Duplicate chapter titles never merge nonadjacent ranges (Task 1).
- Auto/ambiguous cards do not expand results or become evidence (Task 1).
- Project/document changes, marked text and edited return targets remain safe (Task 2).

### Task 1: Scoped retrieval and conservative anchors
Files: create Workspace/SourceSearch.swift and SourceSearchTests.swift; extend Knowledge/SourceAnchor.swift.
Interfaces: SourceSearch.results(query:in:origin:cursor:scope:purpose:limit:) throws -> [SourceSearchHit];
SourceAnchor.exactRange(for:in:revision:) -> NSRange?.
- [x] RED: fixture scopes, literal/alias ordering, excluded trash, bounded future context,
  UTF-16, repeated headings, corrupt metadata, duplicate/stale anchors and cancellation.
- [x] Run isolated swift test --filter SourceSearchTests; observe missing API failures.
- [x] Implement pure search, exact original anchors, cancellation and stable tie-breaks.
- [x] Focused/full swift test, swift build and MINTBench build; review diff inline.
- [x] Commit, push Draft PR stacked on #230 and attach; record evidence.

### Task 2: Native source navigation
Files: create Editor/SourceNavigation.swift and SourceNavigationTests.swift;
modify EditorSearchJump/ProjectNavigatorView/ContentView/BlockTextView as needed.
Consumes Task 1 hits and exact resolution. Produces native capture/jump/return routes for #112.
- [x] RED native selection/scroll return, source duplicates/edits, wrong project,
  A→B→A stale callbacks, IME and same-document undo preservation.
- [x] Run isolated focused tests; implement minimal editor request bridge.
- [x] Focused/full tests, app/bench build, release developer bundle and isolated smoke.
- [x] Inline whole-issue review, commit/push attached Draft PR; save handoff.
