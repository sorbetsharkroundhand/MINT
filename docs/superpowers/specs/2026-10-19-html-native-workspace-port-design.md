# Native port of the Purlory HTML interaction system

## Authority and intended result

The owner's 2026-10-19 correction makes the supplied HTML an executable behavioral
specification, not a palette reference. The result is a native Swift/AppKit workspace
with the same spatial model, gestures, controls and visual feedback. The previous
single-editor/frame implementation does not satisfy this contract.

Source: `/Users/ryujekyeong/Downloads/purlory.html`, 3,737 lines, SHA-256
`8639aac6eddc5c47c3581e7ccb7190f875890bed6c86fcf1b6e231ae9d7a34e8`.
The complete inline CSS, markup, state and JavaScript were inspected. External CDN
scripts are dependencies of the example, not instructions to execute or add to Purlory.

The existing project remains the sole manuscript owner. No WebView replacement,
mock manuscript, hardcoded fictional knowledge, hidden feature cap, or alternate
single-document layout constitutes completion.

## Source-to-native coverage

| ID | HTML source | Required native behavior |
| --- | --- | --- |
| T01 | `state.columns`, `normalizeStackRatios`, 1051–1133, 1237–1243 | Ordered columns, optional fixed width, independently weighted vertical slots; documents and tools share one layout. IDs are stable and unique. |
| T02 | `ensureDocumentPanelElement`, 1333–1405 | One live native editor per open document, independent text selection, scroll and Undo, active-document dot/title/background, 32-point draggable header, 26-point status. |
| T03 | `openDocumentAlongside`, 1407–1436 | Opening a closed document creates a flexible column after the last document column; opening an existing document focuses it without duplication. |
| T04 | `openAllProjectDocumentsSideBySide`, 1438–1455 | Open every nontrashed document; retain existing positions and append only missing tiles. |
| T05 | `closeDocumentPanel`, 1457–1497 | Close a tile without deleting its manuscript. Keep at least one open document. If active closes, activate the first remaining document. Collapse its row/column space. |
| T06 | `togglePanelVisibility`, 1499–1565 | Navigator, character bible, narrative and margin can coexist. Navigator opens first at 204 points. Other tools stack in the rightmost tool-only column or create a 256-point column. |
| T07 | `renderTilingWorkspace`, 1567–1680 | 8-point outer padding/column gaps; 6-point row gaps. Flexible document columns divide remaining space. Independent native scrolling within each tile. |
| T08 | `startPanelTilingDrag`, `detachGrabbedWindowAndEatVoid`, 1684–1988 | Header drag begins after 5 points; buttons/fields do not start it. Detach the grabbed tile visually, animate its old space closed and track a compact labeled cursor pill. Preserve the live editor. |
| T09 | `evaluate2DDropTarget`, 2024–2076 | Workspace edge bands: 36 points. Top 28% of a target stacks above; bottom 28% stacks below; middle left/right halves insert columns. Expanded preview gap retains the current target with 8-point tolerance. |
| T10 | `applyLiveWindowSizeAdjustment`, 2078–2113 | Neighbors resize live to show the insertion space: flexible for documents, 204-point preview for tools, half-slot height for a vertical insertion. No opaque full-tile drag rectangle. |
| T11 | `commit2DPanelDrop`, `restoreDetachedWindowToOrigin`, 1904–1930, 2115–2182 | All six insertion targets; unique tiles; split target weight using `max(0.25, oldWeight/2)` then normalize. Single-column navigator-origin swaps retain source semantics. Missing target restores origin; a retained last valid target remains usable as in mouseup. Escape always cancels. |
| T12 | `startNavigatorFileDrag`, `previewNavigatorListSpaceOnHover`, 1950–2022 | Drag a file to open/reposition it; within navigator, show 14-point before/after spacing and reorder documents. Suppress the click generated after a drag. |
| T13 | `syncProjectDocumentOrderWithOpenColumns`, 2184–2205 | Reading order is column-major. Reorder open documents only in their existing project-array positions; preserve closed and trashed document positions. Persist through ProjectSession. |
| T14 | `startColumnWidthResize`, 2240–2271 | Prefer the fixed neighboring column; otherwise freeze the left flexible column's measured width. Clamp navigator 165–320, documents 260–1600, tools 210–420. |
| T15 | `startRowSplitResize`, mousemove, 2273–2293, 2482–2492 | Resize adjacent rows using the initial combined weight and column height; each retains at least 20% of their combined weight. Double-click gives the adjacent pair equal shares. |
| P01 | `dockPouchToEdge`, 2298–2366 | Freely draggable pouch docks to the nearest of four edges; orientation changes between vertical/horizontal. Edge gap 8, chrome exclusion 36, normalized position retained across resize. |
| P02 | `startPouchDrag`, mousemove/up, 2368–2376, 2580–2618, 2750–2792 | After 4 points, collapse the tool buttons into a 44×44 M orb while dragging. Suppress the post-drag click. Clamp the orb to the visible screen. |
| P03 | `suckWindowIntoPouch`, `unfoldWindowFromPouch`, 2378–2444 | Dragging the orb outside the writing window by more than 4 points collapses the window into it. Clicking the orb restores the same window/editors. Native close/minimize controls expose this same action. Quit remains real quit. |
| P04 | `toggleMaximizeMacosWindow`, 2446–2450 | Native zoom/full-screen control, followed by pouch redocking; use real macOS window geometry, not a fake desktop inside the content view. |
| E01 | `startParagraphSlipDrag`, mousemove/up, 2209–2236, 2497–2541, 2629–2680 | Paragraph grip drag starts after 6 points. Before/after target preview opens 26 points; move across/between documents; Option copies; a document's sole paragraph copies. Keep block and inline/media/math source intact. |
| E02 | `checkManuscriptTextSelection`, 2798–2860; markup 709–725 | Floating selection bar with bold, italic, quote, polish and excerpt, preserving selection when clicked. Keep additional existing formatting accessible through native menus. |
| E03 | `clipSelectionToResearchNote`, 2887–2916 | Append the selected source as a quote to a real reference/note document, open it alongside and reveal/highlight the excerpt. Never append to an arbitrary manuscript if no note exists; create a blank note. |
| E04 | `decorateTextWithEntityPeeks` through `hideEntityPeekImmediately`, 2920–2996 | Hover existing source-backed entities: badge, name, role, note, tags, source jump. Keep popup alive while entered; dismiss after 190ms; highlight matching paragraphs in every open pane. No hover during typing or drags. |
| E05 | `onParagraphKeydown`, `onParagraphInput`, 3100–3171 | Native editing, Enter and empty-paragraph Backspace, quote marker transformation; preserve whitespace, IME and Markdown rather than copying the example's lossy `innerText.trim()` path. |
| E06 | `centerParagraphIfTypewriter`, `toggleTypewriterScroll`, 3173–3190 | Global typewriter toggle; current paragraph centered when typing/selection changes; top/bottom breathing room equivalent to 26%/38% of viewport height. |
| E07 | `toggleFocusDimming`, CSS 301–306, 3232–3235 | Global paragraph focus: inactive paragraphs opacity .24, hovered .68, active paragraph fully visible. Decoration only; no persisted text changes. |
| E08 | `setWhisperTypingMode`, 2455–2470; CSS 194–211 | Typing dims chrome/headers/status to .08 and pouch to .06; pouch stops pointer actions. Pointer movement greater than 8 points restores it. Keyboard/assistive access remains available. |
| E09 | `triggerInlineGhostSuggestion`, accept/dismiss, 3237–3268 | Explicit local continuation at active cursor. Keep real Purlory Tab accept / right-arrow partial / Escape reject and composition gating. Never use random sample continuations. |
| E10 | `updateManuscriptStats`, 3210–3230 | Each tile displays its own character count, goal progress ring, hover reading time (450 chars/minute, minimum 10 seconds) and paragraph count. Default goal 500; persistent user goal if set. |
| N01 | `updateChromeAndNavigatorHighlight`, 2998–3031 | Project/current document title, open-document count, selected file highlight, open markers, active tile style stay consistent across all actions. |
| N02 | `selectDocument`, `selectDocAndJump`, 3305–3336 | Open missing target alongside, activate and reveal exact original evidence; .9-second flash; preserve return point. Never jump to a guessed match. |
| N03 | `createNewDocument`, 3338–3352 | Create a real blank document and open alongside. Hardcoded example prose is fixture data, never a creation template. |
| N04 | quick command functions, 3354–3471 | Cmd-K palette: commands, files, characters, original paragraphs; title/detail/category filtering, first 9 results; arrow wrapping, Enter, Escape, outside click, hover selection. Existing Ask/source search remains reachable. |
| N05 | `toggleExpandItem`, `renderToolPanelsContent`, 3473–3578 | Compact expandable character/event/margin cards, a shared expanded item, active-paragraph synchronization and exact-source jumps. Existing writer-owned edits and records remain accessible. |
| N06 | `addNewCharacterPrompt`, 3480–3495 | Add an editable blank native character record through ProjectWriterEditing; never invent the example's ship repairer. |
| N07 | `toggleColorScheme`, 3580–3584 | Immediate theme switch from the pouch and palette; preserve explicit user palette/font customizations. |
| A01 | coauthor modal markup 905–929, functions 3614–3667 | Prompt → generating/result/error → explicit Insert. Append result as real paragraphs in the captured document; no implicit insert or fake fallback. Cancel/stale project/document/body results cannot publish. |
| A02 | `polishSelectedTextWithAI`, 2861–2885 | Rewrite the captured selected range only if project/document/body/range still match; one undoable action. Show unavailable/error instead of fabricated success. |
| A03 | `callLivingMarginAiInsight`, 3669–3696 | Explicit margin generation tied to captured original evidence. Retain existing source validation, cancellation and quiet uncertain-inference policy. |

## Native architecture

1. **Layout model and geometry.** `SpatialWorkspaceLayout` is a Codable value of
   ordered columns and weighted slots. `WorkspaceTileID` distinguishes document IDs
   from tool IDs. Pure operations implement open/close/insert/reorder/resize and
   pure geometry implements hit testing. Presentation does not own manuscript text.
2. **Persistent native canvas.** A flat AppKit canvas retains a native host per tile,
   changes frames from geometry and never rebuilds/reparents an editor when a tile
   moves between columns. Horizontal/vertical overflow keeps every tile reachable
   when minimum sizes exceed the window. No unannounced single-editor fallback.
3. **Document ownership.** Extend ProjectSession with explicitly keyed document
   edits and atomic multi-document transactions; never route an inactive binding
   through `selectedDocument`. Each native editor owns a separate undo manager.
   Active selection alone controls completion, indexing, diagnostics and commands.
   Focus activation attaches those consumers synchronously; passive layout changes
   never change selection, commit marked text or reload the editor.
4. **Drag transactions.** Store a complete origin layout plus captured project key.
   Detach and insertion previews are transient. Release commits one mutation;
   Escape/cancel restores the exact origin. Project changes invalidate the gesture.
   Resize, paragraph, panel and pouch gestures are mutually exclusive.
5. **Pouch window.** A native nonactivating panel follows the writing window and can
   survive outside its bounds while the window is hidden. It never holds a second
   manuscript owner. Collapse retains all editor hosts; restore returns focus and
   selection. Closing the app/project cleans up panels and monitors.
6. **Editor extensions.** Typed presentation/options and callbacks connect paragraph
   transfer, selection actions, hover and focus decoration. Knowledge queries and
   generation live in workspace controllers, never BlockTextView or EntryStore.
7. **Persistence.** A versioned project-keyed layout preference stores tile order,
   widths/weights, pouch edge/position, goals and focus/typewriter toggles separately
   from manuscripts. Invalid/duplicate/missing/trashed IDs normalize safely. Old
   sidebar preferences seed first use; stored documents/UserData are never rewritten
   as a migration side effect. Project changes cancel work and clear native hosts.

## Appearance and motion

Use the HTML's paper/obsidian palette, serif/UI/monospaced typography, quiet hierarchy,
8/6-point spacing, 7/9/13-point radii, 36-point window chrome and 32-point tile headers.
Restore the source's active/inactive tile distinction without neon outlines. Default
new-workspace text measure is 680 points, size 18.5 and spacing 8; explicit user font
preferences take precedence. Opaque manuscript content remains required; materials
are restricted to window chrome and transient tools, without stacked glass.

Ordinary proportional layout changes use .30 seconds and cubic timing
(.25, 1, .5, 1). Void collapse .28; grab-to-pill .24; unfold-to-tile .32; app collapse
.36 with (.4, 0, .2, 1); app restore .38. No bounce/tilt/squish. Cursor following uses
the source's spring coefficients (pouch dragging 640/50, dock 280/34, pills 720/54),
dt clamped .004–.030. Motion stops after settling; no idle timer. Reduced motion uses
direct layout/fades and reduced transparency uses opaque surfaces. Real native
window metrics replace simulated desktop padding and traffic-light geometry.

## Conflicts and deliberate correctness repairs

- The HTML calls Gemini externally; the repository requires local inference. The
  owner explicitly chose the existing local AI. Coauthor, polish and margin keep
  their explicit generation/review/apply interactions through the ready local
  engine. No remote client, automatic model setup or sample fallback is introduced.
- HTML uses translucent manuscript cards; the repository explicitly requires opaque
  manuscripts. Match the composited color and active state with opaque native paper.
- Duplicate `startNavigatorFileDrag` definitions (1950 and 1971), the slip Y update
  using X velocity (1195), lossy text trimming, fake AI fallbacks, index-sensitive
  reorder and equalization are implementation defects, not desired interactions.
  Preserve the interaction intent with correct native ownership and atomic edits.
- Generic project storage must remain independent of Fiction. Tool data is adapted
  from existing writer records/verified knowledge, with original EvidenceAnchor /
  SourceAnchor identity. Paragraph locations/hashes never become persistent document IDs.
- Literal demo defaults (two particular open chapters, authored characters/events,
  sample notes) are used only in isolated fixtures. Real first use opens the selected
  document, and an adjacent real document if available; never fabricate user content.

## Acceptance evidence

Completion requires more than passing old styling tests. Deterministic tests cover
every layout operation/edge boundary, gesture rollback, origin/last-target behavior,
multi-document edit ownership, independent Undo, cross-document atomic transfer,
IME retention during layout, stale project/body rejection, preference restoration,
all controls/commands and source navigation. Property-style operation sequences must
preserve unique tile IDs, positive finite weights, a live document and user text.

Use synthetic native windows to exercise actual header/resize/file/paragraph/pouch
gestures, multiple live editors, no-model/General writing, reduced motion and both
themes. Capture actual native results with two columns, vertical stacks, mixed tools,
drag preview and restored pouch. Existing image/math/import/export/recovery and Ghost
tests remain required. Then run `swift build`, `swift test`, `swift build --product
PurloryBench`, standard app bundle, boot smoke and actual UI smoke in CFFIXED_USER_HOME.
No real manuscript, model choice, human IME/VoiceOver acceptance, or Store proof is
inferred. Commit and push the authorized feature branch after the verified full port.
