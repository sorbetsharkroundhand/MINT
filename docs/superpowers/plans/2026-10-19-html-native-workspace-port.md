# HTML Native Workspace Port Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. The owner's
> executable HTML is the supplied design contract; this plan records its literal
> native translation. No subagents, external publication or main merge.

**Goal:** Port the complete HTML spatial workspace and interaction system to Swift.
**Architecture:** Pure layout/gesture state and a persistent flat AppKit canvas,
keyed ProjectSession transactions, native pouch panel, workspace-owned editor tools.
**Tech Stack:** Swift 6, SwiftUI, AppKit/TextKit 1, existing local MLX inference.
**Spec:** `docs/superpowers/specs/2026-10-19-html-native-workspace-port-design.md`.

## Global Constraints

- Existing ProjectSession is the only manuscript owner; no WebView or fake content.
- General and no-model writing, Hangul IME, Ghost keys, source anchors, autosave,
  recovery, round-trip and project/generation cancellation remain required.
- Retain all existing writer-data access; no dependency or manuscript schema migration.
- Source thresholds and motion values are in the spec; preferences override font defaults.
- Use isolated synthetic projects and CFFIXED_USER_HOME for native app verification.
- Gemini/local policy is awaiting the owner's answer; independent native work proceeds.

## Review Focus

- A queued inactive editor binding after another document activates must edit only its key.
- Layout reparenting must never destroy native IME/selection/undo state.
- Moving rich blocks across documents must be atomic and undoable, including media/math.
- Cancelling a drag, changing projects, or receiving stale AI output must leave text intact.
- Too many columns/rows and a hidden main window must keep all documents and the pouch reachable.

### Task 1: Spatial layout and gesture model

**Files:** Create `Workspace/SpatialWorkspaceLayout.swift`, `SpatialWorkspaceGeometry.swift`,
`SpatialWorkspaceController.swift`, and corresponding tests.
**Interfaces:** Produces `WorkspaceTileID`, ordered columns/slots, six-way drop targets,
geometry frames, reversible drag state and project-keyed layout persistence.

- [ ] Write failing tests for open/all/close-last, simultaneous tools, all insertions,
  normalized splits, navigator reorder, minimum/maximum resize, 20/80 row bounds,
  pair equalization, corrupt preferences, exact cancel and unique tile sequences.
- [ ] Run `swift test --filter SpatialWorkspace`; observe missing/new behavior fail.
- [ ] Implement pure model/geometry and controller; no manuscript/UI ownership here.
- [ ] Run the same tests; require zero failures; commit the slice.

### Task 2: Keyed document transactions and persistent multi-editor canvas

**Files:** Modify `ProjectSession.swift`, `ContentView.swift`, `BlockTextView.swift`,
`WorkspaceShellView.swift`; create `SpatialWorkspaceCanvas.swift` and native tests.
**Interfaces:** Consumes Task 1 frames/IDs. Produces retained per-key tile hosts,
explicit document bindings, activation callbacks and independent undo managers.

- [ ] Write failing tests for concurrent A/B editing, active-only Ghost attachment,
  undo isolation, preserved editor identity/marked text during tile moves/resizes,
  keyed stale writes, trash/project transitions and overflow reachability.
- [ ] Run new tests and watch failure before changing production code.
- [ ] Add keyed session edits and atomic captured-body transactions; adapt EditorPane
  for an explicit key; attach consumers on native activation; render flat retained hosts.
- [ ] Run new tests plus existing project/IME/identity/ownership tests; commit.

### Task 3: Actual tile, navigator and resize gestures

**Files:** Native canvas interaction, `ProjectNavigatorView.swift`, tile headers,
`SpatialWorkspaceInteractionTests.swift`.
**Interfaces:** Consumes retained hosts and layout controller; produces pointer
transactions, insertion preview, labeled cursor pill, file reorder and resize handles.

- [ ] Add failing actual-event tests for 5-point panel threshold, six-way targets,
  preview tolerance, detach/void collapse, last-valid drop, Escape restoration,
  navigator open/reorder and active-editor preservation under repeated movement.
- [ ] Implement gestures and proportional animation, preserving all source thresholds.
- [ ] Run the new interactions and geometry suite; commit.

### Task 4: Movable four-edge pouch and native window lifecycle

**Files:** Create `WorkspacePouchController.swift`, pouch native view and tests;
modify `WorkspaceRail.swift` and window host integration.
**Interfaces:** Consumes layout/tool toggles; produces nonactivating native panel,
docked orientation/position, 44-point drag orb and reversible window collapse.

- [ ] Add failing tests for 4-point threshold, edge choice, ratio clamps, screen changes,
  outside-window collapse, click restore, focus/IME preservation and panel cleanup.
- [ ] Implement local event handling, measured native coordinates, settled motion
  and existing close/minimize/zoom integration; preserve real app termination.
- [ ] Run native lifecycle and layout tests; commit.

### Task 5: Paragraph transfer and writing presentation

**Files:** Editor extension(s), `WorkspaceParagraphTransfer.swift`, presentation
state/decorations, selection toolbar, transaction and native interaction tests.
**Interfaces:** Consumes explicit keys/native editor registry and original source
mapping; produces atomic move/copy, drop preview, typewriter, focus and whisper.

- [ ] Add failing tests for 6-point paragraph drag, before/after, same/cross-document,
  Option/sole-paragraph copy, rich Markdown/media/math preservation, atomic Undo/Redo,
  stale body/project rejection, IME, 26/38% typewriter padding and dim/wake thresholds.
- [ ] Implement through existing native editing/source conversion, without lossy text
  replacement or Knowledge logic in BlockTextView. Add toolbar toggles and per-tile stats.
- [ ] Run editor/paragraph/undo/media/math tests; commit.

### Task 6: Commands, entity resonance, cards and explicit assistance

**Files:** Workspace command palette, entity presentation and assistance controllers;
selection toolbar, existing verified tool adapters and focused tests.
**Interfaces:** Consumes existing source search/knowledge/WriterData and local-ready
engine. Produces source-backed navigation/hover, excerpt, generation/result/insert.

- [ ] Add failing tests for Cmd-K search categories/9-result limit/wrapping/escape,
  opening the correct tile/source, 190ms peek lifetime, cross-pane matching, shared
  expansion, selection formatting/excerpt and source-backed generated actions.
- [ ] Reuse real writer/knowledge data, local inference admission and engine policy;
  no random continuations or fake fallback. Add captured-key/body cancellation and
  explicit insert/undo for coauthor/polish, honoring the owner AI-policy answer.
- [ ] Run new tests and existing search/source/Ask/margin/diagnostic tests; commit.

### Task 7: Native fidelity, regression matrix and delivery

**Files:** Theme/font/layout integration, actual UI smoke additions, verification
record with source-ID coverage and generated native screenshots outside tracked source.

- [ ] Audit every spec row T01–A03 against actual production wiring and tests; fix
  missing paths rather than describing them as future work.
- [ ] Review the whole diff inline for ownership/stale callbacks, lost rich source,
  resource cleanup, nonfinite geometry and accidentally hidden existing features.
- [ ] Run full build/test/bench, standard bundle, isolated boot and actual UI smoke.
- [ ] Exercise real native spatial gestures and capture both themes/mixed stacks/
  drag preview/pouch restore; distinguish automated evidence from human acceptance.
- [ ] Commit and push `codex/mint-editorial-redesign`; verify remote HEAD and clean status.
