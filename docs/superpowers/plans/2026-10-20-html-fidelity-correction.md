# Native workspace fidelity correction

The supplied `mint.html` is the reference for visual appearance and native workspace interactions. Source SHA256: `8639aac6eddc5c47c3581e7ccb7190f875890bed6c86fcf1b6e231ae9d7a34e8`.

## Latest owner direction, 2026-10-20

After running the application, the owner prioritized reliable manuscript tile grabbing, a less transparent Liquid Glass surface, and the established editor/caret behavior. The owner explicitly requested implementation only, with no further tests or verification; the owner and Gemini will perform validation. The earlier instruction to push remains in effect. This revision is not a verified candidate, and no build, automated test, app smoke or screenshot run was performed after this direction.

The supplied review discusses an earlier independent desk/pinned-card design. Those descriptions do not replace the actual HTML's two-dimensional tiling state machine. Do not introduce an unrelated pinned-card system by treating quoted review text as new implementation requirements.

The owner subsequently clarified that the supplied optimization must preserve the HTML's interaction behavior. Keeping a translucent source tile and drawing a drop guide instead of opening real space was incorrect. The current correction restores immediate tile detachment, proportional live space allocation and collapse as the pouch crosses the window boundary. No build, test or runtime verification was performed for this follow-up.

## Implemented changes

### Caret alignment and pouch follow-up, 2026-10-21

- Derive the active-line band, custom caret and Ghost baseline from the same
  TextKit line geometry. An insertion rectangle's top is not necessarily the
  glyph ascender line. Honor upstream affinity at soft wraps and use the new
  font's baseline for an empty extra fragment instead of scaling the previous
  paragraph's metrics.
- Pouch collapse retains the native first responder without manually unmarking
  Hangul composition or synthesizing `didChangeText`. The HTML's suction and
  floating orb remain presentation operations on the retained window.
- Trace the reported two quantization messages to the bundled Kiwi archive and
  its pinned `CoNgramModelBase::create` implementation. Its main and noun models
  request unsupported quantization before falling back. A private constructor
  adapter now selects the same FP32 implementation explicitly. Matching public
  headers and allocator definitions are pinned; models and archive are unchanged.
- These changes are source implementation only. No build, test, native execution
  or visual verification was performed, as requested by the owner.

### Existing port

- Translate chrome, navigator, tile headers, labeled actions, compact character/event/margin cards, source-backed entity peeks, palette and coauthor presentation into SwiftUI/AppKit. Bundle the source typefaces and audited Lucide icons.
- Preserve legacy author records, writer tools, modes, AI controls and diagnostics in secondary entry points. Keep project characters visible across documents, and return focus after closing record editors.
- Keep captured-source assistance on existing local inference. Coauthor requires explicit insertion; explicit polish and margin actions run inline with stale-result guards. Preserve coauthor prompt text while reopening the panel.
- Use retained native editor hosts for two-dimensional layout. After the HTML's 5-point threshold, capture the grabbed tile once for the 240 ms minimize animation and hide its live host. Its old column/row disappears and neighboring tiles expand; entering a drop target shrinks neighboring tiles to reserve real space. No translucent source tile or painted drop rectangle remains. Release unfolds the tile from the moving pill over 320 ms; Escape restores the original layout.
- Keep pointer coordinates unpublished and publish preview changes only when the target changes. Give insertion columns stable identity, cache geometry by layout and viewport, and stop rebuilding resize handles during dragging. Native proportional frame animation remains active for actual layout changes; optimization does not replace it with a fixed canvas.
- Keep the independent four-edge pouch, orientation changes, native whole-window collapse/restore and floating collapsed orb. Install an app-level drag monitor before hiding the original buttons. The pouch becomes a 44-point orb after 4 points of movement; crossing the window boundary immediately starts its 360 ms whole-window suction. Consume the completed drag's mouse-up so it cannot activate restore. Track the pointer in desktop coordinates independently of the moving panel.
- Keep the orb visible across application deactivation before hiding the main window. Reuse one window image for the 380 ms restore, preserve the retained live editor and selection, and invalidate old animation completions when collapse/restore is interrupted. If capture fails, restore still resets the live window's opacity.
- Mirror the editor's workspace style into the layout manager's drawing snapshot, so quote decoration does not read actor-isolated editor state from the drawing override.
- Increase outer-window glass density: native Regular glass, with light tint alpha 0.82–0.88 and dark tint alpha 0.86–0.90. Keep manuscript surfaces opaque for writing legibility.
- Restore native text line fragments rather than imposing the HTML's fixed CSS line box. Keep natural line spacing, explicit author formatting, Hangul IME, selection, undo, Ghost and manuscript serialization on the established editor path.
- Give text insets one owner. The previous port alternated window-width and tile-width breakpoints in separate callbacks. The editor now computes its horizontal inset once, while workspace decoration no longer rewrites it.
- Restore normal writing's 25% bottom scroll room. Explicit typewriter mode uses the existing native caret rectangle and immediate scrolling, instead of queued animations targeting the middle of a paragraph. Ordinary tool/toast updates do not recenter the editor.

## Source mapping

| HTML source | Native implementation |
| --- | --- |
| `.mint-liquid-glass-window`, `.mint-object-card`, chrome and navigator templates | `WorkspaceLiquidGlass`, `WorkspaceSpatialChrome`, `SpatialTileHeader`, `ProjectNavigatorView` |
| `spawnWindowMinimizeGhost`, `detachGrabbedWindowAndEatVoid`, `applyLiveWindowSizeAdjustment`, document mousemove/mouseup handlers | `SpatialWorkspaceCanvasView`, `SpatialWorkspaceController`, `SpatialWorkspaceGeometry` |
| Pouch drag, four-edge docking, whole-window suck/unfold | `WorkspacePouchController`, `WorkspacePouchView`, `WorkspacePouchGeometry` |
| Character/event/margin templates and entity peek | `WorkspaceCharacterCards`, `WorkspaceNarrativeCards`, `WorkspaceCompactCard`, `WorkspaceEntityController`, `LivingMarginView` |
| Quick-command and coauthor markup | `WorkspaceQuickCommandPanel`, `WorkspaceAssistancePanel` |
| Selection format popover and paragraph slip | `SelectionToolbarView`, `WorkspaceEditorInteraction`, `WorkspaceParagraphTransfer` |

## Validation handoff

On 2026-10-21 the owner authorized building after supplying a log from
`codex/mint-editorial-redesign`. That log already completed the MINT build and
included the new `builder.cpp`; the reported output contained an AppKit font
Sendable warning and a Kiwi character-conversion warning. Move native fonts to
the main-actor-owned `NSMutableAttributedString` and make the guarded BMP cast
explicit in the vendored header, recording its local patch in provenance.
`swift build` then rebuilt both changed sources and linked MINT and MINTBench
successfully (12.51 s), with no warnings or errors in that invocation. No tests,
application launch, pouch interaction or visual alignment checks were run.

Earlier targeted runs and native captures informed the implementation but do not establish the correctness of this revision. The changes initially delivered under the owner's implementation-only instruction are now compiled by the build-only follow-up above, but have not been exercised. Existing regression coverage and the updated isolated UI script remain available for the owner's validation. The HTML sample is stored only as a test fixture; it is not shipped as author data.

Production adaptations are actual documents and writer records instead of fictional samples, existing local inference instead of Gemini, restrained readable glass, and the owner's requested preservation of native editing mechanics. Browser security rejected the local HTML URL; source was read directly without an alternate browser route or server workaround.
