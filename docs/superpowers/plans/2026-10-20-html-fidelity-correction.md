# Native workspace fidelity correction

The supplied `purlory.html` is the reference for visual appearance and native workspace interactions. Source SHA256: `8639aac6eddc5c47c3581e7ccb7190f875890bed6c86fcf1b6e231ae9d7a34e8`.

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
| `.purlory-liquid-glass-window`, `.purlory-object-card`, chrome and navigator templates | `WorkspaceLiquidGlass`, `WorkspaceSpatialChrome`, `SpatialTileHeader`, `ProjectNavigatorView` |
| `spawnWindowMinimizeGhost`, `detachGrabbedWindowAndEatVoid`, `applyLiveWindowSizeAdjustment`, document mousemove/mouseup handlers | `SpatialWorkspaceCanvasView`, `SpatialWorkspaceController`, `SpatialWorkspaceGeometry` |
| Pouch drag, four-edge docking, whole-window suck/unfold | `WorkspacePouchController`, `WorkspacePouchView`, `WorkspacePouchGeometry` |
| Character/event/margin templates and entity peek | `WorkspaceCharacterCards`, `WorkspaceNarrativeCards`, `WorkspaceCompactCard`, `WorkspaceEntityController`, `LivingMarginView` |
| Quick-command and coauthor markup | `WorkspaceQuickCommandPanel`, `WorkspaceAssistancePanel` |
| Selection format popover and paragraph slip | `SelectionToolbarView`, `WorkspaceEditorInteraction`, `WorkspaceParagraphTransfer` |

## Validation handoff

### Pouch manager and unified search objects, 2026-10-21

The owner's new interaction replaces the HTML's title-click command palette:
the outer glass window title is now a passive drag region. Remove its search
button and the Command-K binding. The pouch search button, Command-F and project
search entry points open the same persistent canvas object. It offers current
document matches, project documents/characters/originals, and tool commands.
Current-document search uses an immutable native-text snapshot, supports every
literal occurrence including code, and validates its revision before selecting
an exact native range. Project hits reuse original-source evidence navigation.
Debounced, cancellable background searches suppress marked input and discard
stale project results. Arrow keys, Enter, previous/next buttons and Command-G
share result navigation; selecting a result leaves the search object open.
Newly opened search/settings objects are scrolled into view without replacing
the manuscript editor. The older standalone palette remains available only to
its existing direct compatibility callers, not the spatial UI routes.
The existing source-inspection/question interface remains accessible from the
pouch's all-tools menu and Option-Command-K, preserving its evidence-based AI
question workflow alongside the unified find object.

Clicking a canvas object selects a pouch destination without intercepting its
mouse event or stealing editor focus. One spring carries the pouch between
objects and can be retargeted while moving. At the destination, the orb widens
into a tinted shoulder shape; its actual AppKit view moves from the floating
panel into the canvas. The panel is then hidden, leaving no separate window
shadow, outline or connector at rest. The shape overlaps the object's lower
edge, with reserved space below rows so it does not cover the next object.
Canvas animation, scrolling and resizing update the attachment geometry.
Reduced motion attaches immediately. Dragging the pouch detaches it; dragging
outside the main window retains the existing suction/collapsed-widget lifecycle.

The attached pouch exposes search and object settings directly. Its M grip
opens all tools, including theme, coauthoring and document arrangement. A new
settings object follows the selected object and reuses the existing writing,
autocomplete, character, narrative and margin controls. Shared editor settings
are labeled as applying to all manuscripts. Clicking the settings object itself
preserves the object being inspected. Empty-space selection or the release
action returns the pouch to its independent edge position.

`swift build` completed successfully (13.37 s), linking Purlory and PurloryBench with
no warnings or errors in the final invocation. Existing title-click and row-gap
test expectations were updated for the requested behavior. Tests, live model
inference and actual-app interaction checks were not run under the owner's
build-only instruction; motion appearance, rapid retargeting, IME search, native
focus and collapse/restore still need the owner's runtime review.

### Disable automatic first-line indentation, 2026-10-21

The owner requested flush prose paragraphs. Remove the font-sized first-line
indent from fiction manuscripts and rename that presentation policy to
`continuous`. Preserve its paragraph spacing and Hangul word wrapping, along
with manual whitespace, explicit alignment and structural block insets.
Update the existing typesetting assertions for empty paragraphs, font changes,
Enter after headings and document switches to expect zero first-line indent.
`swift build` succeeded (18.32 s). Tests and actual-app checks were not run,
consistent with the owner's build-only instruction.

### Restore visible completion controls, 2026-10-21

The owner requested the pre-redesign editor's autocomplete in the spatial
workspace. Source comparison confirms that `EditorPane` still embeds the same
`PurloryBlockEditor`, with `CompletionController` edit/selection callbacks, local
inference, inline Ghost rendering and Tab/right-arrow/Esc handling intact.
The spatial tile's `showsChrome: false` removed the original toolbar, including
its model status and autocomplete controls. The reference HTML's header has
typewriter, focus and manual continuation actions, so restoring the older
model controls is an explicit addition requested by the owner.

Reuse `ModelChip` in each document header to expose enable/disable, model
selection/download/retry, prediction length and generation/load status. Below
520 points, use compact controls while retaining accessible labels and tooltips.
Keep the native draggable header separate from the model button. Opening the
model controls or invoking a header action focuses that tile's existing editor;
manual continuation only proceeds after focus succeeds. No editor replacement,
selection rewrite, new inference path or automatic authorization is introduced.

`swift build` completed successfully (17.05 s), linking Purlory and PurloryBench.
Per the owner's build-only instruction, no tests, model inference or actual-app
interaction checks were run. Completion behavior and popover/focus interaction
still require the owner's runtime review.

### First-character caret and pouch theme follow-up, 2026-10-21

The owner's captures showed the active decoration above the first typed line
and an empty-document prompt at a different origin. Remove that prompt entirely.
Selection updates previously measured overlays before rendered-block line-height
updates, and native insertion/IME callbacks could measure an unfinished layout.
Resolve overlays after block rendering and after native input calls unwind,
coalesce a final post-edit refresh, and synchronize once TextKit draws the glyphs.
Keep geometry updates nonanimated and restart the blink only for editing, focus
or actual caret movement, not every redraw. Attribute edits/undo also schedule
the same post-layout refresh. No manuscript characters are rewritten.

Do not replace typing attributes during marked text. Caret height continues to
use the input font's cap height, ascender and descender, including custom inline
sizes; during composition, read the composing character's actual font. The
stroke remains two points wide. Baseline measurement precedes the native
insertion-rectangle query so both observe the completed layout.

The separate pouch panel now receives an explicit light/dark AppKit appearance
from its current theme surface. Its grip also receives the resolved palette,
preventing hover refreshes from reverting to the default light palette. Existing
theme-based surface, border and accent colors remain shared by rail and orb.

`swift build` completed successfully (18.69 s), linking Purlory and PurloryBench without
warnings or errors in that invocation. Per the owner's build-only instruction,
actual-app typing, IME, visual checks and automated tests were not run; the
reported first-character behavior still requires the owner's runtime review.

### Paragraph highlight and soft returns, 2026-10-21

The owner's screenshot showed a background starting before the actual indented
text. Replace the container-wide single-line band with the union of TextKit's
used line fragments in the active native paragraph. This follows first-line
indentation, alignment, wrapping and mixed font metrics. The empty line after a
terminal soft return belongs to that same background; Enter starts a new one.

Keep Enter's existing block inheritance and list continuation. Route Shift+Enter
through AppKit's input method and then `insertLineBreak`, inserting U+2028 through
the normal text input/undo/autosave path. LF remains the paragraph separator.
The source persists both characters verbatim, without migrating existing text.
Alignment/font wrappers accept the internal line separator on reload and prose
projection; EPUB emits `<br />` inside the original paragraph. Caret/Ghost geometry
also recognizes the empty visual line after a terminal soft return.

`swift build` compiled the final source and linked Purlory and PurloryBench successfully
(15.55 s). Verification remains build-only at the owner's request; no tests or
actual-app interaction checks were performed for this change.

### Persistent pouch widget follow-up, 2026-10-21

The owner clarified that dragging the pouch outside the main window must leave
a persistent desktop widget, with the original window stored inside it. Source
inspection found that `AppDelegate` unconditionally allowed termination after
the last window closed, while the suction path hides the main window and closes
a temporary animation panel. The delegate now keeps the application alive while
a workspace is collapsed. Explicit Quit still uses the existing save/drain path.

An application-owned pouch lifetime retains the controller and hidden original
window. SwiftUI bridge removal cannot dispose a collapsed widget, and a new bridge
adopts the retained controller by window identity. The panel remains floating,
visible across deactivation/application hiding and Spaces, and outside window
cycling. Clicking it or reopening from the Dock restores and activates the same
editor window. The HTML's 360 ms suction, 380 ms unfold and 44-point orb remain.

The owner authorized build-only verification for this follow-up. `swift build`
compiled the final changes and linked Purlory and PurloryBench successfully (13.14 s),
with no warnings or errors in that invocation. Runtime/UI checks and tests
remain unperformed.

On 2026-10-21 the owner authorized building after supplying a log from
`codex/purlory-editorial-redesign`. That log already completed the Purlory build and
included the new `builder.cpp`; the reported output contained an AppKit font
Sendable warning and a Kiwi character-conversion warning. Move native fonts to
the main-actor-owned `NSMutableAttributedString` and make the guarded BMP cast
explicit in the vendored header, recording its local patch in provenance.
`swift build` then rebuilt both changed sources and linked Purlory and PurloryBench
successfully (12.51 s), with no warnings or errors in that invocation. No tests,
application launch, pouch interaction or visual alignment checks were run.

Earlier targeted runs and native captures informed the implementation but do not establish the correctness of this revision. The changes initially delivered under the owner's implementation-only instruction are now compiled by the build-only follow-up above, but have not been exercised. Existing regression coverage and the updated isolated UI script remain available for the owner's validation. The HTML sample is stored only as a test fixture; it is not shipped as author data.

Production adaptations are actual documents and writer records instead of fictional samples, existing local inference instead of Gemini, restrained readable glass, and the owner's requested preservation of native editing mechanics. Browser security rejected the local HTML URL; source was read directly without an alternate browser route or server workaround.

### Folder-index pouch correction, 2026-10-22

The owner superseded the separate settings-object design: the pouch must become
an index label on the selected object's edge and own that object's controls.
The settled pouch now sits above the object's top edge, with a flared folder-tab
contour. Its base overlaps eight points of the object's surface and blends into
that exact surface color, without an independent border, shadow or stacked glass.
The reserved vertical space moved from below each row to above it; opening tools
does not add a tile, resize the manuscript or replace its native editor.

The pouch itself hosts an expandable native control area. Manuscripts expose
Format, AI, View and Object index labels: selected-text colors, size, bold,
italic and code; paragraph styles, lists, alignment and spacing; local model and
autocomplete settings, continuation, polish and embedded coauthoring; typewriter,
paragraph focus and default typesetting. All formatting reuses BlockTextView's
existing transactions and marked-text guards. The spatial selection popover and
document-header controls are retired; legacy editor formatting remains intact.

Character and narrative edit sheets are replaced by their existing durable writer
editors inside the pouch. Context, margin, navigation and search expose relevant
controls there. The legacy inspector enum remains decodable, but saved layouts
remove that presentation-only object and old command routes open the pouch.
Existing tests/capture helpers and smoke selectors were adapted to these routes;
they were not executed, per the owner's build-only instruction.

The same spring, native canvas attachment, four-edge detached docking and retained
collapsed-window lifetime remain in use. Expansion obeys Reduce Motion. Detaching
an expanded pouch starts from its index lip, and hiding focused tool controls
returns focus to the original native editor. `swift build` compiled the final
source and linked Purlory and PurloryBench successfully (12.99 s), with no warnings or
errors in that invocation. No runtime, IME, visual or UI interaction checks were
run for this revision.

### Index pouch refinement, 2026-10-22

The owner's screenshot and follow-up authorize a focused refinement of the
folder-index interaction. The frontend-design, apple-design and emil-design-eng
skills informed proportions, material continuity, motion and control ownership.
The original HTML's critically damped movement and retained 360/380 ms workspace
collapse/restore transitions remain the motion reference.

- The manuscript index is at most 276 points wide; reference-object labels are
  at most 188 points. Readable ink, a discrete all-tools grip and short scope-aware
  labels replace the wide, low-contrast gray toolbar. The accent is composited
  into the actual theme surface, rather than making translucent palette tokens
  opaque. The joined surface has one contour and no additional glass layer.
- An expanded pouch reserves space above its object. The native host translates
  downward without changing its width, height, editor instance or text layout;
  subsequent rows move with it. The body continues behind the host's top corners.
  A single 240 ms layout transition supplies both surfaces' frames, including
  interrupted openings/closings. Tool content keeps a stable layout while the
  contour reveals it; narrow objects use a vertical, scrollable arrangement.
- Standard buttons retain native tracking and keyboard focus. Only the grip and
  blank label area initiate pouch movement. A 7-point threshold distinguishes a
  grab, and the desktop orb preserves its grab offset. An approaching pouch can
  be grabbed; Reduce Motion still settles immediately.
- Format applies to the selection/paragraph; Environment explicitly applies to
  all manuscripts. The enclosing window's duplicate coauthor/layout controls are
  removed, with those routes retained in the pouch's all-tools menu. Coauthor
  opens the prompt directly, including when invoked from that menu.
- Pouch visibility no longer owns or cancels coauthoring. Session-local drafts
  are retained per project/document across tab and object changes. Runtime and
  source invalidation still cancel generation; interrupted or stale drafts stay
  readable but cannot be inserted. Stored runtime identity and activation epoch
  prevent an ABA source change from reauthorizing an old result. This is not a
  new disk-persisted draft format. Existing stale-source test expectations now
  require retained text and rejected insertion; they have not been executed.

Validation remains build-only at the owner's request. No application launch,
screenshots, native interaction, IME checks or test execution were performed.
The final `swift build` completed successfully in 12.09 seconds and linked Purlory
and PurloryBench without warnings or errors in that invocation.

### Seamless overlay correction, 2026-10-23

The owner's latest direction supersedes the reserved accessory space and the
slower transitions described above. The selected object's perimeter now has a
small continuous rise around its index controls. A shared surface below the
persistent native host and controls above it use the object's exact theme color;
the accent fades into that surface without a separate tab border or shadow.

The pouch is entirely out of layout flow. Opening its tools changes neither tile
frames nor the canvas scroll extent. Ordinary eight-point object spacing replaces
the pouch-specific top and row gaps. Tools overlay the object's content, while
pointer events outside the visible controls pass through to the native editor.
Compact objects use accessible icon controls, and titles truncate before the
index instead of colliding with it. The all-tools menu retains new-manuscript
creation when the navigator's inline action is covered by its index.

Object headers retain a minimal close button; expanded tools have their own close
button. Unmodified Escape dismisses tools first, then the selected object. The
last manuscript folds the retained window into the floating desktop pouch instead
of discarding content or destroying the window. Marked text, Ghost rejection,
media/math editing and paragraph dragging retain their existing Escape handling.
Closing tools preserves coauthor drafts and returns tool focus to the editor.

Object creation and tool/control reveals use 120 ms transitions. Selection no
longer sends the pouch flying across the writing area. Object closure is immediate,
neighbor layout settles in 120 ms, and window folding/restoration uses 120/140 ms.
Reduce Motion continues to bypass these transitions.

The final `swift build` completed successfully in 14.91 seconds and linked Purlory
and PurloryBench, with no warnings or errors in that invocation. Existing geometry
expectations now cover unchanged frames and scroll extent when tools open, but
tests were not executed. No application launch, screenshot, native interaction or
IME check was performed, in accordance with the owner's build-only instruction.

### Vertical pouch popover, 2026-10-24

The owner's new specification replaces the index label and seamless contour
entirely. Selection now exposes one compact pouch trigger. Clicking it opens a
304-point popover with a uniform dark surface, a subtle one-point border and
15-point corners. There is no gradient, contour mask, section tab bar or shared
object silhouette. The detached pouch still follows the application theme and
retains four-edge docking and the independent collapsed-window widget.

The fixed header shows the current object/document name, an all-tools menu and
a separate close button. Titles truncate within their own space; neither button
can be pushed outside the card. The body shows AI Writing, Formatting/Paragraphs
and Manuscript/Tools together as compact icon/title/status rows. Section headings
provide immediate coauthor, bold and new-manuscript actions. Formatting values use
native menus. Model management, coauthor drafts and author-data editors expand
within the same scrollable card, retaining their existing operations and state.
An ordinary opening starts with the overview; explicit writer-edit and coauthor
commands still reveal their requested controls. Search objects retain their own
context instead of redirecting the pouch to the active manuscript.

The card remains out of layout flow and may extend across a narrow object's edge.
Its position and height are clamped to the visible canvas; it moves above its
trigger when there is sufficient room there. The trigger hides if a constrained
viewport requires the card to cover it. New objects and resize handles cannot
cover the popover. Manuscript hosts, text layout and scroll extent are unchanged.

The close button, Escape and outside clicks dismiss the card without a closing
animation. A second Escape no longer closes the manuscript/window. Native marked
text, Ghost and media/math Escape handling retain priority. Opening uses only an
80 ms content fade, bypassed with Reduce Motion. Tool focus returns to the native
editor, and closing the card does not discard or cancel a coauthor draft.

Updated regression sources cover viewport fitting for narrow and lower objects,
tab removal, simultaneous action availability, unchanged tile geometry and
synchronous dismissal. Existing smoke selectors now reach the all-tools menu
through the popover header. Neither tests nor the smoke script were executed.
The final `swift build` linked Purlory and PurloryBench successfully in 13.38 seconds,
with no warnings or errors in that invocation. No application launch, screenshot,
IME or interaction verification was performed under the owner's build-only scope.

### Pouch refinement priorities 1–4, 2026-10-24

The owner approved all four priorities in the supplied review. This supersedes
the fixed dark surface, fixed height and window-button behavior described above.
The 304-point card now uses the current theme's opaque pill surface, a subtle
border and an 18-point shadow. Its body measures its content; the viewport caps
the resulting height. The opening edge is selected from the available space and
stays fixed as inline content changes. The trigger remains outside the card.
Embedded author-data controls and generated coauthor results share the outer
card's scrolling instead of introducing separate fixed-height scroll regions.

Bold, italic, inline code, font size, paragraph headings, quotation and ink colors
are direct controls. Selected formatting uses the theme accent and accessible
state labels. Typewriter scrolling, paragraph focus and autocomplete have native
switches. AI actions distinguish composition, authorization, model-loading and
memory-pressure states. Existing editor commands and marked-text guards remain
the action boundary; the manuscript editor is not replaced.

The pouch trigger is a native tile-header action, with its own layout space and
28-point hit area. No overlay hides neighboring header controls. Native window
close and minimize buttons retain their original targets and actions. The last
manuscript's close action closes its window. Window-to-orb collapse remains
available through the explicit all-tools action and the existing outside-window
drag, preserving the retained editor and floating widget. Drag completion also
clears the header trigger's pressed state when the gesture monitor consumes the
mouse-up event.

Paragraph hover, selection and focus fades invalidate the affected paragraph and
gutter rectangles. Presentation changes invalidate visible paragraphs only when
the relevant state changes. Animation regions expire when motion settles; layout
changes rebase active regions. Tile frame transitions, pouch movement, pointer
following and paragraph fades now use a view-bound display link rather than
fixed 60 Hz timers. Paragraph grip targets are 28 by 28 points. This changes the
redraw strategy; no runtime performance or frame-rate improvement is claimed.

Regression sources were extended for measured height, stable popover anchoring,
native window actions, header placement and paragraph damage bounds. They were
not executed. The final `swift build` linked Purlory and PurloryBench successfully in
15.63 seconds, with no warnings or errors in that invocation. No tests, application
launch, UI automation, screenshots or IME checks were performed under the owner's
build-only scope. The pre-existing `Package.resolved` changes are excluded.

### Rectangular grain overlay correction, 2026-10-24

The supplied 3182-by-1984 screenshot shows a faint rectangular tint crossing
multiple opaque objects and ending near half the window's width and height.
Unobstructed card pixels change from RGB (243, 241, 235) outside the rectangle to
approximately (238, 236, 230) inside it, consistent with the grain overlay's 0.022
opacity. The whole-workspace overlay stretched an SVG `feTurbulence` image through
AppKit's `NSImage` rendering path; the HTML instead uses a repeating background.

The grain now uses a cached, deterministic monochrome Core Graphics tile repeated
in view coordinates at the original opacity. It redraws on resize and clears its
own transparent backing-layer damage before repainting, preventing repeated tint
accumulation. Glass and manuscript background colors are unchanged. Regression
sources cover all-quadrant texture coverage at 1x/2x, resizing, and partial-redraw
stability. They were not run. `swift build` succeeded in 15.22 seconds with no
warnings or errors. No application launch or visual reproduction was performed;
the renderer diagnosis is based on the supplied screenshot and source inspection.
