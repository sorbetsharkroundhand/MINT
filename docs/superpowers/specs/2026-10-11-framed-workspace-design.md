# Framed Workspace and Navigation Rail — #163

Status: approved by the owner on 2026-10-11; detailed plan review is pending.

## Owner intent and scope

The owner deferred model selection to a later manual decision and chose
**framed workspace and navigation rail UI redesign** over a layout-only
refactor or focus-mode expansion. Deliver a visible, editor-first workspace
change using the existing functional routes. Follow #163's presentation
direction without treating model, Store, or integrated RC gates as complete.

The selected outcome comprises a small persistent left rail, a framed opaque
manuscript, and a navigator card that adapts to available space. Supporting
presentation state and geometry work belongs to this outcome; a policy-only
refactor is not the final deliverable. #163 remains an epic for later work.

## Current seams and evidence

- `WorkspaceShellView.swift` combines layout rules, accessibility materials,
  drag state, and project/runtime composition.
- `EditorToolbar` owns global navigation, original search, saved writer-data
  access, and Settings alongside document-local title/model controls.
- Sidebar visibility is shared through `mint.sidebarVisible`; width, selected
  tool, placement, and chrome visibility already have persistent keys.
- `ProjectNavigatorView` currently occupies the window's titlebar row and
  hardcodes 74 points of leading header padding. A navigator card needs its
  own local header geometry, distinct from the actual window controls.
- Side-tool fit excludes its rendered 1-point divider. Added rail/frame
  geometry makes a single complete width budget necessary.

## Approach and alternatives

Use a persistent rail with adaptive cards. Keeping the entry points visible
supports keyboard navigation and reopening a hidden navigator. A hover-revealed
rail would require another discovery/focus contract; a complete morphing shell
would introduce more animation and state transitions than this scope needs.

Deliver the outcome through small inline PRs: presentation/layout support,
framed shell, then functional rail integration. Each PR must stay buildable
and within approximately 500 changed lines. Do not introduce a new UI package
or perform the entire #163 redesign at once.
Keep the approved spec and detailed plan in a separate preparation PR if adding
them to the first implementation slice would exceed that review budget.

## Visible structure

```text
Native window controls and drag region / project title
┌────────┬────────────────┬──────────────────────────────────────┐
│ Rail   │ Navigator card │ Opaque manuscript frame              │
│        │                │   document toolbar                   │
│ Files  │ Project        │   same TextKit editor                │
│ Search │ Documents      │   writing status                     │
│ Saved  │                │                                      │
│        │                │ Existing tool, when explicitly opened│
│Settings│                │                                      │
└────────┴────────────────┴──────────────────────────────────────┘
```

- Reserve a 52-point shared window-chrome row. Place its project title after
  the measured traffic-light safe region. Keep native window buttons and a
  native drag region; do not replace window behavior with custom gestures.
- Rail width is 56 points, outer inset and surface gaps are 10 points, and
  frame corner radius uses `MintRadius.lg` (12 points). Buttons have at least
  a 32-by-32-point hit area.
- The manuscript frame has an opaque `editorSurface` fill and a restrained
  separator border. Frame decoration must not clip the TextKit editor's
  selection, math/media, or transient controls.
- Navigator header actions (project switching, new document, trash) remain
  inside the navigator card. Remove the obsolete window-button offset there.
- Use the approved Pretendard UI, Noto Serif KR manuscript, and existing mint
  accent. Preserve custom palettes. Use at most one material layer for chrome;
  cards use solid surfaces and Reduce Transparency has an opaque fallback.

## Rail actions and ownership

- **Files:** toggle the existing navigator preference. Show a visible selected
  state and an accessible show/hide label. Opening does not move the manuscript
  caret; closing returns focus to the same editor without resetting selection.
- **Original search:** reuse the existing model-free source search action and
  its caret-capture behavior. Explicit search may focus the search surface.
- **Saved writer information:** reuse `WriterCompatibilityMenu` for character
  and work information, writer decisions/history, and suggestion sources.
  Preserve access to all existing writer-owned data.
- **Settings:** use the standard Settings action at the bottom of the rail.
  Existing menu shortcuts remain available.

Move these global entry points out of `EditorToolbar`. Keep document title,
the existing long-paragraph notice, and model status in the document toolbar.
No empty Map, Review, Agent, or Living Margin destination is introduced.

## State and persistence boundary

Introduce a small immutable presentation snapshot consumed by geometry and
views. Its inputs are navigator visibility/width, validated tool selection,
preferred tool placement, and chrome visibility. It has no document identity,
manuscript, project mutations, inference owner, or filesystem access.

Retain `mint.sidebarVisible`, `mint.sidebarWidth`, `mint.sidebarSection`,
`mint.toolDockPosition`, and `mint.chromeHidden`. Their stored values remain the
source of truth; do not add a second persisted model or silently rename keys.
Preserve valid saved values. Unknown/deferred tool values render no active tool
without overwriting the raw preference or deleting any writer data.

Remove startup normalization that unconditionally resets a valid tool choice
to Files. Window-size fallback is derived and never writes preferences. Width
preferences remain 250 by default with existing 200–360 limits, drag resistance,
and collapse hysteresis at 150/176 points.

## Adaptive geometry and transitions

- At workspace widths below 1,024 points, a visible navigator overlays the
  leading side of the manuscript frame. It does not reduce the editor's layout
  width. The rail always provides a close/reopen path.
- At 1,024 points and above, place the navigator inline when its clamped saved
  width leaves at least 560 points for the manuscript. Otherwise use overlay.
- Include outer insets, the rail, all gaps, navigator allocation, tool width,
  and dividers when deciding whether a side tool fits. Preserve the existing
  bottom fallback and explicit floating/bottom preferences in this scope.
- Keep bottom/floating height limits at 320/520 points. This scope does not
  redesign utility content or add compact/expanded utility states.
- Editor and visible navigator each stay in one structural slot when geometry
  changes. Overlay/inline switching must not recreate either view or discard a
  pending navigator rename/search. Visibility changes retain existing closure
  behavior while preserving document selection and editor identity.
- Reuse the existing navigator transition only where meaningful. Reduce Motion
  applies the same state transition without spatial animation. Correctness
  cannot depend on animation completion; no new typing/caret/Ghost animation.

## Source responsibilities

- `WorkspacePresentationState.swift`: immutable validated presentation inputs.
- `WorkspaceLayoutPolicy.swift`: complete geometry budget and derived placement.
- `WorkspaceFrame.swift`: frame decoration and shared native window-chrome row.
- `WorkspaceRail.swift`: accessible functional global entry points.
- `WorkspaceShellView.swift`: stable view composition and transient drag state;
  `WorkspaceSurface` retains the connection to the existing project owner.
- `ProjectNavigatorView.swift` and `ContentView.swift`: remove obsolete global
  chrome assumptions and consume the new presentation boundary.

Extract only these concrete seams; keep existing runtime and command ownership.
Retain the custom shell for this scope. NSToolbar migration remains a separate
feasibility decision under #163 rather than a prerequisite for this UI change.

## Verification and acceptance

Add failing regression coverage before each new behavior. Use isolated synthetic
projects and preferences; never real manuscripts. Tests must cover:

- valid/unknown persisted choices and startup preservation;
- widths 860, 1,023, 1,024, 1,180, and 1,440, navigator hidden/visible, all tool
  placements, complete side-fit boundaries, and preference restoration;
- rail action routes, keyboard reopen/search, accessible labels and selected
  states, and disabled search when the project is not editable;
- the same native editor instance, document identity, selection, undo history,
  and visible navigator field state across frame/rail/width transitions;
- Reduce Motion, Reduce Transparency, light/dark/custom palette behavior, window
  control clearance, and existing General/AI-disabled operation.

Run focused tests, `swift build`, `swift test`, and `swift build --product
MINTBench` with automatic resolution disabled. Preserve required CI. Merge only
after required CI succeeds under the owner's existing authorization.

Actual app launches remain deferred to the requested combined verification
batch after these implementation slices. At that point verify keyboard-only,
VoiceOver, real Hangul marked text, Ghost Tab/right-arrow/Esc, cursor/selection,
undo, narrow/default/wide windows, native dragging/full screen, and visual
quality. Deterministic/native fixtures do not claim final manual acceptance.

## Deferred work

Manual focus-mode expansion, automatic chrome quieting, morphing navigator,
adaptive utility redesign, advanced Story Intelligence, model selection,
Store submission, and the final integrated RC remain separate. Existing focus
mode and menu shortcuts keep their current behavior. Execute inline without
subagents, as instructed in #163.
