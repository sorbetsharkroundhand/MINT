# Workspace Layout Policy — #163, First Slice

Status: proposed for owner review; product implementation has not started.

## Intent and execution scope

The owner has deferred model selection to a later manual decision and requested
the next UI/UX or internal functionality issue. This slice follows that request
without treating the model, Store, or integrated RC gates as complete. It starts
the presentation work described in #163; it does not complete that epic or
change the first-release acceptance recorded in #119.

The immediate outcome is a single deterministic policy for the geometry of the
existing writing workspace. A side tool must leave the manuscript at least 560
points wide, including the tool's divider. The current navigation, placement
preferences, focus behavior, and editor instance remain stable.

## Evidence in the current implementation

- `WorkspaceShellView.swift` contains placement enums, layout calculations,
  accessibility-sensitive surfaces, drag presentation, and runtime composition.
- The maximum navigator width calculation is duplicated in
  `WorkspaceLayoutState.navigatorWidth(in:)` and the resize-divider setup.
- `effectiveToolDock` budgets 340 points for a side tool, while the shell also
  renders a 1-point divider. At a workspace width of 1,150 and navigator width
  of 250, it selects a side tool even though only 559 points remain for the
  editor. The minimum-width frame then exceeds the available width.
- Bottom and floating tool heights are calculated directly in the view, away
  from the other geometry rules. Toolbar density also uses the layout helper.

These are concrete seams and a boundary inconsistency, rather than a reason to
introduce a new design-system framework.

## Approach

Extract the existing value types and calculations to
`Sources/MINTCore/Workspace/WorkspaceLayoutPolicy.swift`. Keep existing internal
type names (`ToolDockPosition`, `WorkspaceToolbarDensity`, and
`WorkspaceLayoutState`) so this slice does not require a wider API migration.

Add shared geometry helpers to the existing `WorkspaceLayoutState`:

- `navigatorMaxWidth(in availableWidth: CGFloat) -> CGFloat`
- `bottomToolHeight(in availableHeight: CGFloat) -> CGFloat`
- `floatingToolHeight(in availableHeight: CGFloat) -> CGFloat`
- `toolSeparatorWidth: CGFloat`, equal to 1
- `floatingToolInset: CGFloat`, equal to 18

The shell consumes those helpers for its frames, divider, padding, and resize
limit. `effectiveToolDock` includes `toolSeparatorWidth` in the side-fit budget.
The toolbar continues to evaluate density from its actual editor width.

The policy owns geometry only. `WorkspaceSurface` continues to own bindings to
the existing presentation preferences, and `ProjectSession` continues to own
document identity, manuscript changes, and persistence. `WorkspaceMotion` and
the material surfaces remain outside the geometry policy.

Alternative approaches are a full framed-shell migration or a new mutable
presentation model. Both involve more UI identity or preference coordination
than this first slice needs. They remain later #163 slices.

## Exact behavior

- Navigator defaults to 250 points; limits remain 200–360 points and continue
  reserving 560 points for the editor. Existing drag resistance and collapse
  hysteresis at 150/176 points remain unchanged.
- Side tools use 340 points plus a 1-point divider. With a visible 250-point
  navigator, automatic/left/right placement falls back to bottom at 1,150
  points and fits at 1,151 points. Without a navigator, the boundary is 901.
- Bottom and floating preferences remain explicit. Narrow-window fallback
  never rewrites the saved side preference; widening restores it.
- Bottom height remains `min(320, availableHeight * 0.4)`. Floating height
  remains `min(520, max(240, availableHeight - 36))`, with 18-point padding.
- Toolbar density remains compact below 840 points of actual editor width.

## Verification and delivery

First add failing regressions for the exact side-fit boundaries in the existing
`WorkspaceLayoutTests`, run them against the unchanged production implementation,
then extract and correct the policy. Cover automatic/left/right preferences,
visible/hidden navigator, and restoration after widening. Keep current drag,
height, density, theme, routing, and editor coverage green.

Run the focused workspace tests, `swift build`, `swift test`, and
`swift build --product MINTBench`, all with automatic resolution disabled. The
required CI remains unchanged. Actual local app launches and manual IME,
VoiceOver, visual, and focus checks remain in the owner's requested combined
verification batch; deterministic tests do not replace those checks.

Create one bounded PR, approximately 500 changed lines or fewer, including the
spec/plan. Follow #163's inline execution instruction without subagents. Merge
only after the required CI succeeds under the owner's existing authorization.
Keep #163 open for presentation state, framed shell, rail, adaptive utility,
focus/motion, and final native accessibility acceptance.

## Constraints

No dependency changes, manuscript migration, new model defaults, new toolbar,
editor replacement, animation changes, or preference-key migration are included.
Keep the manuscript opaque and preserve editor focus, selection, undo, Hangul
marked text, and Ghost acceptance/rejection semantics.
