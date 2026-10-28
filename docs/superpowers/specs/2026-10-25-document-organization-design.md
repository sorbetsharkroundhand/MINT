# Restore document organization in the native navigator

The owner requests the pre-redesign document browser's usable features inside the
current document object. Reuse the existing project owner, retained editors and
spatial canvas. Do not revive EntryStore as a second mutable owner.

## Scope

- Nested folders, creation inside a folder, disclosure, persistent expansion,
  inline/double-click renaming, move-to-folder/root menus and drag reordering.
- Drop documents into folders; drop one document onto another to group them;
  spring-open folded destinations. Keep dragging documents into the spatial canvas.
- Document creation by current kinds (manuscript, note, reference), creation date
  editing, kind switching, Markdown/EPUB export, local search and recent projects.
  Legacy journal/novel distinctions map to current document kind/project mode;
  a document action must not silently change the whole project's mode.
- Trash and restore whole folder trees, individual documents, confirmed permanent
  deletion/emptying, and undo for reversible organization changes.
- Optional local AI naming after grouping, cancellable and stale-safe, without
  loading/downloading a model or competing with foreground writing.
- Recover organization/dates from the verified legacy snapshot when a migrated
  project has no new organization record. Never touch entries.json in place.

## Architecture decision

Use a versioned generic navigation record in durable project UserData. Existing
schema-2 readers preserve opaque UserData and backups already carry it. Extending
the manifest would impose a needless storage-version migration; using preferences
for folders would lose writer-owned organization during export/recovery.

Use the current native document drag path with folder-aware destinations. Folder
reordering stays inside the navigator. All mutations are project/epoch scoped;
cycles, stale targets and malformed metadata cannot silently discard organization.

Keep the present quiet surface, icons, compact rows and editor selection. Preserve
existing notes and assets. No actual-app, UI or test execution: compile only as
previously requested, update regression source, then commit/push this branch.
