# Calm writing environment and fixed pouch

The owner's implementation brief supersedes the earlier no-indent, permanent
paragraph-highlight and draggable attached-pouch directions. Keep native editor
identity, selection, IME, Ghost acceptance, undo and storage unchanged.

1. Typography: default line spacing 11.5 pt, 60 pt vertical inset, one-em first-line
   indent and 0.22-em paragraph spacing for continuous prose; 0.65-em spacing for
   spaced prose; negative tracking only for H1/H2. Preserve saved user settings.
2. Calm surface: remove persistent paragraph fill, expose paragraph grips and
   entity decoration only with Option, make focus opacity cursor-only, and wake
   hidden chrome only after more than 48 pt of pointer movement or an explicit click.
3. Single sheet: one manuscript fills the canvas with no tile header, gutters or
   rounding. Multiple objects retain their existing layout and short transitions.
   Remove shortcut capsules and instructional footer text. Keep counts and goals.
4. Fixed pouch: one non-draggable chrome trigger, compact panel grid/environment
   controls/local AI/footer. Restore selection formatting. Open detailed author
   tools and coauthor separately. Only explicit collapse creates the movable orb.

Add/update regression sources, then compile with `swift build`. Do not execute
tests, launch MINT or perform UI automation under the owner's build-only scope.
Commit and push on `codex/mint-editorial-redesign`; leave unrelated local files out.

## Implementation and delivery evidence

- The fixed chrome button owns the overlay anchor; tile selection does not move
  the card or reset its measured height. The compact card has no scroll container.
- Paragraph transfer requires Option to expose/grab its handle. Command during
  the drag copies the paragraph, avoiding a conflict with the reveal modifier.
  Explicit Option and click interaction wake the surrounding chrome.
- Selection formatting is restored through the existing native selection panel.
  Detailed author editing and coauthor drafts remain reachable in separate tools.
- Collapse is an explicit footer/menu action. Only an already collapsed orb can
  be dragged, and restoration reuses the retained window and native editor.
- Existing saved layouts and font/spacing preferences remain intact. A layout
  containing exactly one manuscript uses the full sheet; opening a reference
  panel restores the existing spatial layout.
- Regression sources cover single-sheet geometry/native identity, focus opacity
  and Option hover, typography, fixed-card geometry, selection formatting, and
  explicit collapse/restore. They were not executed under the build-only scope.
- `swift build` completed successfully on 2026-10-25 in 22.54 seconds, including
  MINT and MINTBench linking. No runtime, IME, accessibility or UI verification
  was performed; those behaviors still need review in the built app.
