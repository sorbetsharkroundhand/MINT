# Native writing diagnostics

Task 11 adds native correctness decorations and explicit, validated correction actions. Runtime-to-margin/settings/editor publication is Task 12. Actual-app paint, IME and accessibility acceptance remains owner-handled later.

## Exact correction authority

`WritingDiagnosticsActions` resolves only a current controller finding and its current alternative. Runtime identity, native revision, profile/provider/rule stamp, post-binding source ownership and editor identity must agree. No anchor search chooses among duplicate quotes. A refusal invalidates only the owned input context and schedules a recheck without resetting the projection or loading a document.

`BlockTextView.applyWritingCorrection` checks composition first and never forces unmark. It verifies one exact mapped source range, the original source/native text, evidence ownership and the alternative. Format-crossing targets and nonuniform native attributes are refused, including code, links and math/media attachments. Word/phrase alternatives cannot introduce Markdown structure or controls. A live attached native undo owner and enabled Undo are required. Edits follow the existing shouldChangeText / attributed native replacement / didChangeText path, grouped as one undoable action with the original attributes. Normal binding/autosave and projection capture handle publication; focus and caret return to the same editor. Ghost key handling is untouched.

## Decoration ownership

Correctness marks are derived native spans held outside NSTextStorage and temporary search/selection attributes. Publication validates exact source/native mapping and current owner/revision, filtering out style findings and unproved spans. Edits, stale owners and composition withhold marks. A sorted/coalesced span layer uses binary search and visits only intersecting visible spans; the layout helper draws a restrained underline in the existing palette danger color and preserves graphics state.

The synthetic headless fixture is 300,000 UTF-16 units with 1,000 spaced marks. One thousand visible-range queries measured 1.956 ms initially, with at most 16 visited entries per query. This measures range lookup, not real paint or IME behavior. Deterministic tests preserve author attributes, exact serialized source, selection, temporary search attributes and Ghost across mark/clear. Hidden AppKit windows provide native undo/serialization ownership; no Purlory application is launched.

Regression coverage includes uniform bold correction with emoji/math/media neighbors, one Undo/Redo, normal autosave commit emission, current alternatives and failed-proof recheck, duplicate quotes after unrelated edits, wrong project/editor, stale revisions, marked text and mixed attributes inside a word.

Final Task 11 verification on 2026-10-16: 189 relevant tests (1 existing skip), full 1,129 tests (2 existing skips), build and PurloryBench passed. The final Undo safety regression covers disabled view Undo, detached native ownership and disabled Undo registration; all refuse without changing source. The word/phrase action conservatively refuses structural marker alternatives; this does not add any automatic replacement.

TextKit exposes a nonisolated drawing override. Optional diagnostic painting is admitted only on the main thread and explicitly enters the main actor to read the derived layer; the drawing code retains value ranges and never reads editor state across actors. Release compilation after this boundary fix reported no compiler warnings, and the full 1,129-test suite, build and PurloryBench passed again.
