# Math editing geometry (#193)

On main `13679de`, the real ProjectSession editor placed the custom caret about
17.4pt above the actual source glyph baseline for `E=mc^2`. Its caret calculation
assumed an ordinary prose line even though math uses enlarged native line
fragments. The live preview appeared outside the math block, below its source,
and the full-width prose line band remained visible during math editing.

The caret now follows TextKit's actual glyph baseline in active math. Prose
retains its existing caret behavior, and the prose line band is hidden in math.
The preview occupies available space beside the source within the same block;
multiline preview uses the whole group. It scales to available width and is
omitted when there is insufficient room, rather than overlapping source or the
next paragraph. Existing math height, source selection, render debounce,
managed manuscript storage and Markdown serialization remain intact.

Regression coverage also exposed a mode-transition bug: after consumed math
markers and temporary graphics disappeared, the plain-text fast path skipped
the math paragraph when the caret left it. That path now includes the previous
math selection so the block returns to rendered mode without a full rebuild.

`MathEditGeometryTests` hosts the actual ContentView/ProjectSession editor. It
checks glyph/caret alignment, retained preview within the source block, prose
highlight restoration, multiline selection and geometry, tall/invalid math,
stable entering/exiting layout, native Undo/Redo and cancelled preview work.
Existing math round-trip and dirty-render tests cover persistence and bounded
refresh. The packaged UI smoke types a single-line math block, switches away
and back, edits its source, sends Undo/Redo and verifies save/quit/relaunch.

Visual feel and real macOS input remain owner checks: edit `E=mc^2`, a fraction,
and multiline math; verify the caret follows the source, the preview belongs to
the same block, and prose below remains readable. Automated evidence does not
claim this owner checkbox.
