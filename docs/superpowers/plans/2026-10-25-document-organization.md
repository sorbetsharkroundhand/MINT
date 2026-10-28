# Document Organization Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore the legacy document browser's organization and document actions in the current native object.
**Architecture:** Versioned generic navigation UserData, mutated only by ProjectSession. Native navigator rows share folder-aware drop destinations with the spatial canvas.
**Tech Stack:** Swift, SwiftUI, AppKit, existing ProjectStore and local completion engine.
**Spec:** `docs/superpowers/specs/2026-10-25-document-organization-design.md`

## Global Constraints

- Preserve native editor identity, IME, body, undo, assets and existing durable UserData.
- Keep legacy import read-only and verified; no Fiction types in generic navigation.
- Build only; do not execute tests or app/UI automation. Push the current branch.

## Review Focus

- Folder cycles/orphans and duplicate identities must be rejected, never hide documents.
- Trashed descendants must restore without reviving independently trashed documents.
- Deferred rename/drop/AI callbacks cannot affect another project or activation epoch.
- Folder moves cannot reorder live editor contents or drop unrelated writer records.
- Existing migrated projects regain folders without overwriting later user organization.

### Task 1: Durable organization and session mutations

- [ ] Add `ProjectNavigation.swift` and `ProjectNavigationEdit.swift` for folders, dates, trash bundles, validation and pure edits.
- [ ] Wire scoped edits, creation metadata and reversible structural undo through `ProjectSession`.
- [ ] Add legacy snapshot preparation through `LegacyProjectMigrator` and regression sources for persistence, cycles, trash/restore and stale edits.

### Task 2: Navigator surface and native interactions

- [ ] Replace flat rows with a flattened folder tree; restore creation, rename, move, date, kind and export actions.
- [ ] Add native folder rows/drop handling and folder-aware document drops without replacing retained editors.
- [ ] Restore trash management, persistent disclosure, search/recent access and local folder naming.
- [ ] Update affected navigator regression sources.

### Task 3: Delivery

- [ ] Compile with `swift build`; inspect changes without executing tests or launching the app.
- [ ] Commit only task files and push `codex/purlory-editorial-redesign`.
