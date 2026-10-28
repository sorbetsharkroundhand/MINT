# Navigator drag UX repair

> Superseded by [legacy navigator parity](2026-10-26-navigator-legacy-parity.md). The user requested the original direct gestures within the current design; the separate extraction control and Option-only grouping below are no longer implemented.

Continue inline on `codex/purlory-editorial-redesign`, preserving all pre-existing changes.

## Reproduced causes and intended behavior

Document-row centers currently request `.inside(document)`, which creates a new folder immediately. Folder rows accept document drops across their entire height. Hit testing searches child row bounds without first confining the pointer to the navigator. The root destination is an unlabelled background/end-of-list region, making extraction hard to discover and reach.

- Ordinary document-row drops reorder. Enter another folder through its own central label area; child rows in another folder do not implicitly reparent documents.
- Preserve document grouping as an explicit Option-drop, checked at release. Keep its existing durable transaction and undo behavior.
- Confine navigator destinations to its visible area. Workspace drops retain the existing open/merge behavior and do not change document ownership.
- Provide a labelled root drop area outside the scroll view and a direct context-menu extraction action. Keep content intact and support undo.
- Show manual order after a successful before/after drag, so alphabetical sorting cannot conceal the result.

## Steps

- [x] Capture current sources and reproduce accidental grouping, folder-edge capture, outside-pane interception and missing visible extraction target with native regression tests.
- [x] Repair hit testing and modifier routing; add the persistent root destination and extraction action.
- [x] Verify native drop/undo, clipped scroll rows, default sorting and deliberate grouping behavior.
- [x] Run build, focused tests, benchmark build and full tests; compare against a fresh pre-change full-suite run because this shared checkout changed since the previous task.
- [x] Review inline, inspect an isolated native navigator render and record results.

Use synthetic projects and `CFFIXED_USER_HOME=/tmp/purlory-navigator-ux-evidence/home`. No real manuscripts or production bundle are needed for these deterministic tests.

Final results: 15 focused cases passed, build and benchmark compile passed, and all 16 pre-existing failing cases remained unchanged in the 1,448-test full run. See `docs/release/navigator-drag-ux-verification-2026-10-26.md` for evidence and review notes.
