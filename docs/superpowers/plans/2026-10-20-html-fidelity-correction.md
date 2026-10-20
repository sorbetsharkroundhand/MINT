# Native workspace fidelity correction

The supplied `mint.html` is the reference for visual appearance and native workspace interactions. Source SHA256: `8639aac6eddc5c47c3581e7ccb7190f875890bed6c86fcf1b6e231ae9d7a34e8`.

## Latest owner direction, 2026-10-20

After running the application, the owner prioritized reliable manuscript tile grabbing, a less transparent Liquid Glass surface, and the established editor/caret behavior. The owner explicitly requested implementation only, with no further tests or verification; the owner and Gemini will perform validation. The earlier instruction to push remains in effect. This revision is not a verified candidate, and no build, automated test, app smoke or screenshot run was performed after this direction.

The supplied review discusses an earlier independent desk/pinned-card design. Those descriptions do not replace the actual HTML's two-dimensional tiling state machine. Do not introduce an unrelated pinned-card system by treating quoted review text as new implementation requirements.

The owner subsequently supplied replacement code for the editor drawing snapshot, pouch drag lifecycle, controller publishing and frozen canvas geometry, and requested applying it. This direction supersedes the earlier live tile-detachment animation: keep the original tile at 0.38 opacity, move a lightweight pill and drop guide, and commit the layout on release. No build, test or runtime verification was performed for this follow-up either.

## Implemented changes

- Translate chrome, navigator, tile headers, labeled actions, compact character/event/margin cards, source-backed entity peeks, palette and coauthor presentation into SwiftUI/AppKit. Bundle the source typefaces and audited Lucide icons.
- Preserve legacy author records, writer tools, modes, AI controls and diagnostics in secondary entry points. Keep project characters visible across documents, and return focus after closing record editors.
- Keep captured-source assistance on existing local inference. Coauthor requires explicit insertion; explicit polish and margin actions run inline with stale-result guards. Preserve coauthor prompt text while reopening the panel.
- Use retained native editor hosts for two-dimensional layout. Track tile dragging through an app-level event monitor, without synchronous tile snapshots. Finish earlier frame transitions before dragging, then keep editor sizes fixed while moving the pill and a noninteractive drop guide. Publish preview changes only when the target changes; pointer updates do not publish. Apply the new layout on release. Escape restores the original presentation.
- Keep the independent four-edge pouch, orientation changes, native whole-window collapse/restore and floating collapsed orb. Defer collapse until release and keep the full rail and its buttons visible throughout dragging. Preserve the pointer's offset from the grabbed rail so button-originated drags do not jump. Recompute the pending collapse from the release point. The live manuscript editor remains the same object.
- Mirror the editor's workspace style into the layout manager's drawing snapshot, so quote decoration does not read actor-isolated editor state from the drawing override.
- Increase outer-window glass density: native Regular glass, with light tint alpha 0.82–0.88 and dark tint alpha 0.86–0.90. Keep manuscript surfaces opaque for writing legibility.
- Restore native text line fragments rather than imposing the HTML's fixed CSS line box. Keep natural line spacing, explicit author formatting, Hangul IME, selection, undo, Ghost and manuscript serialization on the established editor path.
- Give text insets one owner. The previous port alternated window-width and tile-width breakpoints in separate callbacks. The editor now computes its horizontal inset once, while workspace decoration no longer rewrites it.
- Restore normal writing's 25% bottom scroll room. Explicit typewriter mode uses the existing native caret rectangle and immediate scrolling, instead of queued animations targeting the middle of a paragraph. Ordinary tool/toast updates do not recenter the editor.

## Source mapping

| HTML source | Native implementation |
| --- | --- |
| `.mint-liquid-glass-window`, `.mint-object-card`, chrome and navigator templates | `WorkspaceLiquidGlass`, `WorkspaceSpatialChrome`, `SpatialTileHeader`, `ProjectNavigatorView` |
| Document mousemove/mouseup and tile drop targets; subsequent owner-supplied frozen-drag replacement | `SpatialWorkspaceCanvasView`, `SpatialWorkspaceController`, `SpatialWorkspaceGeometry` |
| Pouch drag, four-edge docking, whole-window suck/unfold | `WorkspacePouchController`, `WorkspacePouchView`, `WorkspacePouchGeometry` |
| Character/event/margin templates and entity peek | `WorkspaceCharacterCards`, `WorkspaceNarrativeCards`, `WorkspaceCompactCard`, `WorkspaceEntityController`, `LivingMarginView` |
| Quick-command and coauthor markup | `WorkspaceQuickCommandPanel`, `WorkspaceAssistancePanel` |
| Selection format popover and paragraph slip | `SelectionToolbarView`, `WorkspaceEditorInteraction`, `WorkspaceParagraphTransfer` |

## Validation handoff

Earlier targeted runs and native captures informed the implementation but do not establish the correctness of this revision. Changes made after the owner's implementation-only instruction have not been compiled or exercised. Existing regression coverage and the updated isolated UI script remain available for the owner's validation. The HTML sample is stored only as a test fixture; it is not shipped as author data.

Production adaptations are actual documents and writer records instead of fictional samples, existing local inference instead of Gemini, restrained readable glass, and the owner's requested preservation of native editing mechanics. Browser security rejected the local HTML URL; source was read directly without an alternate browser route or server workaround.
