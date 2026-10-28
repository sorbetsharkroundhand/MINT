> Historical evidence: the names below identify the original tested artifacts, before the Purlory rename.

# Binder drop targets, connected tabs and complex math verification

## Scope

Implemented the owner's follow-up on `codex/mint-editorial-redesign`, preserving existing uncommitted work. No commits, pushes, merges or issue changes were made.

- Manuscripts dropped on a binder header merge into that binder. A native regression exposed mouse-up retargeting after a spatial preview moved the header; stationary tab/list proposals now retain their displayed destination.
- Dropping an open manuscript on the navigator closes only its spatial presentation. Content, document order and trash status remain unchanged. A highlighted outline identifies the destination. Cancellation restores the original layout; leaving the list before releasing does not close a tab. The existing last-open-manuscript guard remains.
- Inactive tabs share the bar background with thin separators only between neighboring inactive labels. The selected tab uses the editor paper surface, rounded top corners and bottom shoulders without a bottom border. Light/dark themes, overflow, close/new/mode controls, quiet typing and native accessibility remain supported.
- SwiftMath supports the nested `aligned`/`pmatrix` environments and dot commands. The supplied pasted equation failed on escaped physical newlines. The shared uncached render adapter converts only those tokens to control spaces, retaining every paired row break. Editor and EPUB rendering use this adapter; serialization, cache keys and EPUB source fallback retain the original LaTeX.
- Display math has a 2-point inset to avoid clipping glyph overhangs. Inline metrics are unchanged; empty math remains empty rather than becoming a padding-only image.

## Verification

- `swift build`: passed.
- `swift build --product MINTBench`: passed.
- Focused workspace, drag, native editor and math tests: **107 passed, zero failures**.
- Complete `swift test`: **1,435 executed, 3 skipped, 46 assertion/error failures across 19 test cases**, including 3 unexpected errors. The failing-case set exactly matches the preceding verification, whose failures were reproduced without the original tab implementation. There are no additional failing cases; all 107 focused cases also passed inside the final whole-suite run. Existing failures remain visible and were not weakened or removed.
- Eight new test cases cover list return/cancel/reopen/last-tab protection; release outside the destination; native header merge after spatial preview; the exact pasted equation and canonical equivalent; LF/CRLF/CR control spaces with one through five backslashes; malformed/empty math; image crop margins; editor round-trip; and EPUB image/original-source fallback.
- Native light/dark tab-strip images and the exact pasted equation image were inspected. The matrix fractions, dots, delimiters and final-row subscripts are visible. These are test-view renders, not actual-app acceptance.

Tests used synthetic projects and `CFFIXED_USER_HOME=/tmp/mint-tabs-math-evidence/home`. The local evidence directory `/tmp/mint-tabs-math-evidence/` contains failing-before-fix logs, final build/benchmark/focused/full-suite logs, `comparison.json`, and the PNG renders. Prior baseline details and the 19 failing test names are in [the original tab verification](manila-tabs-verification-2026-10-25.md).

## Review and remaining acceptance

Inline review checked transaction cancellation and persistence, last-tab protection, manuscript-order callbacks, retained native hosts, tool/navigator routing, and render-only adaptation across foreground and background export. It also checked that formula padding does not change inline metrics or manufacture visible empty math.

Actual-app visual acceptance, physical Hangul IME, VoiceOver and live Ghost keyboard checks remain owner release checks under `docs/release/verification-and-support.md`. No app bundle or shipping model was launched. The pre-existing full-suite failures still prevent an all-green/RC claim.
