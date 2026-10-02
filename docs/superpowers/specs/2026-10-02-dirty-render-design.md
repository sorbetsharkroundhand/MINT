# Bounded dirty media refresh — #18

Current #18 and #99 contracts supersede historical completion claims. Preserve the
landed visible scan, downsample and LRU behavior. Dirty/caret refresh still scans
all paragraphs, raw inline math and marker flags, and resets every prior math group.

Use a small paragraph render index over UTF-16 lengths and block/math-delimiter
metadata. An implicit balanced tree supports bounded lookup and local splice without
shifting every later paragraph after each edit. Keep text/attributes authoritative;
no second project identity or async decoder. Full construction is load/recovery/global
restyle only. Math runs crossing a queried edge expand to preserve group boundaries.

Storage edits update only touched paragraphs and immediate neighbors; invalidation
tracks characters and block attributes, including undo/redo and programmatic edits.
Render dirty, visible, selected/editing media and relevant group neighbors. Inline
folding and temporary/group cleanup must follow the same scopes rather than silently
restore global scans. Preserve persistent line heights and rendering/cache contracts.

Implement in bounded slices: index; editor invalidation; bounded refresh; measured
300k-character/100-media fixture evidence. Use existing tests and frozen #154 measurement
terms where applicable; report synthetic local evidence separately from owner feel.
No decoding subsystem without measurement. Native IME/focus/selection and subjective
long-document feel remain owner validation; no real manuscripts, CI waits or issue
closure. Author design/review runs inline under standing user authorization.
