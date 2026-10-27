# Legacy navigator behavior in the redesigned workspace

Branch: `codex/mint-editorial-redesign`. This supersedes the earlier Option-only grouping and dedicated extraction target. The current design and the shared checkout's newer spatial drag engine remain in place. No commits or remote changes were made.

## Behavior audit

| Legacy capability | Current implementation |
| --- | --- |
| Document reordering | Top/bottom row quarters insert before/after; cross-parent insertion adopts the destination's folder. Successful insertion selects manual sorting. |
| Group two files | Drop on the center of another document without a modifier. Create a folder under the target's parent; target is first, dropped file second. |
| Nested folders | Drop a folder on another folder's center. An expanded folder's bottom also leads into its children; collapsed bottom inserts after it. Invalid ancestor cycles are rejected before preview. |
| Move out of folders | Drop beyond the indentation guide, on the existing bottom boundary, or on empty list background. The corresponding enclosing list receives the document/folder; the leftmost gutter/background reaches root. |
| Spring expansion | Hover a collapsed folder for the legacy 600 ms delay. Leaving or cancelling clears the pending expansion. |
| New folder ordering | Explicitly created folders precede existing sibling folders. Folders produced by grouping follow them, matching the legacy operations. |
| Sorting | Manual, title ascending/descending and date ascending/descending remain available in the current header/context menu. |
| Navigation and editing | Existing search, folder expansion, document/folder rename, creation of manuscripts/notes/references, date editing and kind switching remain available. |
| Trash and export | Existing recursive folder trash, individual/folder restore, confirmed purge/empty, Markdown and EPUB export remain available. |
| Optional folder naming | Grouping and adding a document to an unnamed folder use the existing project-scoped naming request. Its AI consent, ready-engine, busy and stale-result guards remain intact. No model is loaded by these gestures. |

Storage stays with `ProjectSession` and `ProjectNavigation`; legacy `EntryStore` is a behavior reference, not a second mutable project owner. Existing move-menu entries remain available as an alternative to dragging, while the redundant extraction action and footer introduced in the previous attempt are removed.

## Root cause and repair

In the native SwiftUI tree, a row's `visibleRect` can cover its ancestor viewport and exceed the row's own bounds. The previous visible-window hit test used that rectangle by itself. A folder row could consequently claim a drop over a different row, a folder boundary or the surrounding workspace. The resolver now requires the point to lie in both `bounds` and `visibleRect`, and first confines it to the navigator.

Existing indentation guides and bottom dividers now convey hierarchy in the drop resolver as well as visually. Outdenting is checked before self-drop rejection, so dragging a document leftwards out of its own folder row works without requiring another document or scrolling to the end of a long list. Folder subtrees retain their memberships when their enclosing folder moves.

## Verification

The failing regression runs, source snapshots, builds and native capture are stored locally in `/tmp/mint-navigator-parity-evidence/`. The preceding full-suite baseline is `/tmp/mint-navigator-ux-evidence/baseline-failures.json` and its accompanying logs. Native tests use synthetic projects and an isolated `CFFIXED_USER_HOME`.

- Before repair, the direct-gesture regressions failed; an additional new-folder ordering test failed before restoring legacy placement.
- Native tests cover direct grouping/undo, document edges, folder zones, long-list extraction, nested outdent/cancel, moving a whole subtree, existing bottom dividers, spring expansion/cancellation, outside-pane bounds and workspace release after hovering a folder.
- Model tests cover all five sorting modes, folder cycles, rich-body preservation, grouping order, nested metadata round trips and trash/restore behavior.
- A native navigator capture was inspected. The existing tree and folder guides remain; there is no dedicated extraction strip.

- `swift build`: passed (`build.log`).
- `swift build --product MINTBench`: passed (`bench-build.log`).
- Focused navigator, navigation model, spatial/binder, document editing, complex math and naming lifecycle coverage: **52 passed** (`focused-final.log`).
- Complete `swift test`: **1,454 tests, 3 skipped, 33 assertion/error failures across 16 cases**, including 3 unexpected errors (`full-final.log`). The 16 cases exactly match the preceding full-suite baseline; **no new failures**. All 52 focused cases also passed within this run. The comparison is saved as `comparison.json` in the evidence directory. The unchanged case list is recorded in the preceding [baseline report](navigator-drag-ux-verification-2026-10-26.md#existing-whole-suite-failures).

Inline review checked source/window coordinate conversion, clipping against actual row bounds, precedence of enclosing-list boundaries over row/background targets, rejection of ancestor cycles, native folder/document routing, cancellation, undo and manuscript preservation. The canvas change only removes the obsolete grouping modifier argument; the shared checkout's drag-session/geometry machinery is preserved. No tests were weakened to suppress the unrelated suite failures. Existing trailing blank lines in other dirty source files were left intact; the current patch introduces no trailing-whitespace lines.

## Limits

This is native in-process gesture and rendering evidence, not production-bundle physical-mouse, IME or VoiceOver acceptance. The optional ready-model naming path was checked by code audit; these tests do not load a model. The prior full suite has unrelated known failures, which must be reported separately from the focused navigator results.
