# Binder drop targets and complex math follow-up

Implement the owner's follow-up on `codex/purlory-editorial-redesign`, inline, preserving the existing dirty checkout.

## Contract and design

- Dropping a manuscript on a binder header inserts it as a tab. Tab membership changes presentation only.
- Dropping an open manuscript on the navigator object returns it to the document list by closing its spatial presentation. Keep its content, project tree position and trash status. Keep the existing last-open-manuscript guard. Cancel restores the original layout; releasing outside the navigator must not close a tab.
- Inactive tabs share the bar background and have separators only between adjacent inactive labels. The active tab uses the editor paper surface with rounded top corners and outward bottom shoulders. Preserve scrolling, accessibility, close/new/mode controls and dark mode.
- Render the exact supplied nested `aligned`/`pmatrix` source, including escaped physical line endings and repeated row breaks. Preserve source text through editor serialization and EPUB fallback. Use one uncached native rendering adapter for editor and export; keep the editor's main-actor cache separate from background export. Do not change the parser dependency or rewrite manuscript data.

## Execution

- [x] Reproduce the pasted math failure and native navigator-drop failure with regression tests.
- [x] Add an explicit document-list destination with reversible preview, content-preserving close, cancellation and last-tab protection.
- [x] Update the inactive tab drawing to match the supplied connected-tab reference.
- [x] Adapt escaped physical newlines to TeX control spaces in rendering only; preserve paired row breaks.
- [x] Verify editor round-trip and EPUB fallback; share the rendering adapter with export.
- [x] Reproduce image-edge glyph clipping and give display math a small inset, preserving inline metrics.
- [x] Exercise a real native tab gesture crossing a spatial preview before merging on another label; inspect native light/dark and formula renders.
- [x] Run focused regressions, build, benchmark build and the full suite; compare failures with the recorded pre-existing failures.
- [x] Review the final changes inline and record verification evidence and remaining owner acceptance.

Actual-app acceptance, physical IME and VoiceOver remain the owner's release checks. Native tests use synthetic projects and an isolated `CFFIXED_USER_HOME`.

The native gesture regression exposed mouse-up retargeting after preview reflow. Stationary tab/list proposals now remain stable while unchanged spatial and navigator gestures retain their existing routing. Review also found and covered empty math turning into a padded blank image and a remembered tab proposal incorrectly invoking document-order callbacks. Final evidence is recorded in `docs/release/binder-drop-math-verification-2026-10-26.md`.
