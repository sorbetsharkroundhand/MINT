# Project-Owned Runtime Design

**Issue:** [#118 — Ship the project-owned writing runtime](https://github.com/sorbetsharkroundhand/MINT/issues/118)

**Status:** Approved on 2026-09-12

## Goal

A new or returning writer reaches a real, verified Fiction or General project, edits its selected document without configuring a model, saves, quits, and reopens with the same durable manuscript and selection. `ProjectSession` is the only mutable runtime owner of the active project and document. `ProjectStore` is its durable storage actor. `EntryStore` is never a competing owner of a project document.

## Context

The project domain, verified content-addressed store, migration foundation, workspace shell, and project-scoped Intelligence publication guards have landed. The live application remains on the compatibility side of that seam:

- `MINTApp` constructs both `EntryStore` and `ProjectSession`.
- Navigator, editor, commands, export, autosave, and shutdown mutate `EntryStore`.
- `ProjectSession` currently supplies workspace mode and a project/document label for Intelligence, not the editor document.
- The first-run resolver and creation/import coordinators are not connected to the app root.
- The UI smoke fixture writes different project and `entries.json` bodies, then verifies the legacy entry body.
- The initial model sheet still blocks first launch, and an unconfirmed install can reach model-backed completion from typing.

This makes a project-scoped sidecar capable of observing a document owned by a different state graph. UUID membership checks often make the indexer inert, but do not establish a project-owned editor.

## Decision

Cut the normal runtime directly to `ProjectSession`. Do not mirror or dual-write between `EntryStore` and `ProjectStore`.

```text
First Run / Navigator / Editor / Commands
                    |
                    v
              ProjectSession
       active project + selected document
       mutations + autosave + transitions
              |              |
              v              v
         ProjectStore    immutable context
         durable data    |- Completion
                         `- BackgroundIndexer

Legacy Workspace -> EntryStore -> entries.json
        mutually exclusive with the project workspace
```

`ProjectSession` is the sole in-memory authority. `ProjectStore` owns disk serialization and validation but never becomes a second UI model. Derived consumers receive immutable snapshots and cannot mutate the manuscript.

## Runtime State and Identity

Add a stable document key that contains project ID plus document ID. Add a runtime identity that contains that key plus a monotonically increasing generation:

- `projectID: WritingProjectID`
- `documentID: WritingDocumentID`
- `generation: UInt64`

Project and document IDs must always be considered together. Imported libraries can contain identical document UUIDs, so a raw document UUID is not a runtime identity.

The editor and cursor/undo state use the stable project/document key; body edits must not look like document switches. Completion, indexing, persistence, and other asynchronous work use the full runtime identity so an older generation cannot publish after later edits or an A -> B -> A transition.

`ProjectSession` publishes a bootstrap phase:

- `loading`
- `needsProject`
- `ready`
- `suspended`
- `failed(ProjectSessionFailure)`

The session owns the active `WritingProject`, selected document, workspace mode, dirty generation, save phase, debounced save task, persisted per-project selection, and recent project identifiers. External code mutates documents only through session methods.

Document removal is non-destructive. `WritingProject` gains a backwards-compatible `trashedDocumentIDs` collection. Trashed documents remain in the manifest and their immutable blobs are retained. The normal navigator filters them; Trash can restore them. Permanent deletion and retention policy belong to #151.

## Persistence and Transitions

Body and title mutations update the session's in-memory value synchronously on the main actor, increment the generation, and schedule a debounced `ProjectStore.save`.

Every project transition follows this order:

1. Ask registered transition participants to finish marked text, record the cursor, and invalidate transient UI.
2. Cancel Ghost, completion, indexing, and any pending save timer for the old runtime identity.
3. Flush the current dirty project.
4. Load and verify the destination project.
5. Atomically write the active-project marker.
6. Adopt the verified value in memory in a non-cancellable section.
7. Restore the destination selection and position, publish a new generation, and allow new background work.

Failure before activation leaves the old in-memory session and durable active marker unchanged. Once activation commits, adoption must complete even if the initiating task is cancelled.

`ProjectSession.flush()` is the sole project shutdown flush. App termination is deferred until it completes. A failed flush cancels termination and leaves a retryable error visible. Background recovery archives and version retention remain #151.

## First Run and Model Independence

The app root boots through `FirstRunStateResolver` and `ProjectSession`:

- A verified active project opens directly.
- No active project presents Fiction creation, General creation, and legacy MINT library import.
- A corrupt active state presents an actionable error and never silently creates a legacy entry.

The first-run model sheet is removed. Completion authorization is explicit:

- New or previously unconfirmed installs start with completion disabled.
- Existing users who explicitly confirmed and enabled completion keep that setting.
- Bootstrap, creation, import, typing, save, and relaunch never preload, download, or call a model unless completion was explicitly enabled.

Model installation and recovery UI remain #152.

## Creation and Import Transactions

Creation stages a candidate project, saves and verifies it, checks cancellation, then activates and adopts it. Failure preserves the previously active project.

Legacy import is divided into prepare and commit:

- Prepare reads the source without modifying it, copies legacy source/assets into a candidate project, saves it, and verifies it.
- Cancellation is honored before commit.
- Commit atomically activates the verified candidate and immediately adopts it without another cancellation point.

Import failure or cancellation keeps the previous project usable and preserves the original source. The current import contract covers a legacy MINT library/`entries.json`; this change does not claim general Markdown or EPUB import.

## Editor Boundary

`MintBlockEditor` consumes the stable project/document key and a binding backed by `ProjectSession`. EntryStore-specific search types become neutral editor values. Asynchronous editor callbacks additionally capture the full runtime identity when generation-sensitive publication is required.

Before leaving a document, the editor commits marked text and records its position. When runtime identity changes it:

- clears Ghost and transient completion/dialog state;
- prevents delayed callbacks from publishing into the new document;
- resets or isolates `UndoManager` so undo cannot edit the prior document;
- loads the new body and project/document-scoped position.

Native text undo remains intact within a document. Hangul marked text never triggers Ghost, and existing Ghost Tab/right-arrow/Escape behavior remains unchanged.

`WritingPositionStore` stores project/document composite keys. Existing UUID-only position records remain readable as a legacy fallback and are not rewritten destructively.

## Navigator, Commands, Search, and Recent Projects

The project navigator reads `ProjectSession.activeProject` and operates on its non-trashed documents. It supports selecting, creating, renaming, trashing, and restoring documents. Trashing the last visible document creates a replacement blank document before save so the editor always has a valid selection.

Project switching uses a persisted recent-project list. A recent entry is verified before activation; an invalid entry is reported and does not replace the active project.

Menu commands route create, rename, trash, search, export, and print to the active project/document. Formatting continues through the AppKit responder chain. Search runs over an in-memory snapshot of the active project's documents; choosing a result selects that project document before issuing a neutral editor jump.

## Background Work

`BackgroundIndexer` no longer attaches to `EntryStore` in the project workspace. It consumes an immutable selected-document snapshot supplied by the project runtime adapter. Every pass carries project ID, document ID, session generation, and body fingerprint.

Existing project/document/generation publication guards remain authoritative. A project or document transition cancels the old pass before publishing the new identity. A delayed A result cannot publish during B or after A -> B -> A, even when the projects share a document UUID.

Completion receives the same composite identity and clears its context report on every project transition. Derived Intelligence writes only to project-scoped sidecars and never mutates `WritingProject` or `WritingDocument`.

Legacy character decisions and other `JournalEntry`-only fields are not silently projected into Fiction types. They remain accessible through the explicit legacy boundary until #111 supplies their durable project representation.

## Media and Export

Project editing uses an immutable project-scoped asset resolver, never a mutable process-global current-project path.

New image insertion stores and verifies bytes before inserting the body marker. The completion carries the initiating runtime identity; a result for a stale identity is discarded. An unreferenced stored blob is safe, while a document may never reference bytes that failed to persist.

Markdown and EPUB exporters accept a `WritingDocument` plus its project asset resolver. Compatibility overloads remain for the legacy workspace. Imported assets, inline media, and math markup round-trip without falling back to the global legacy image directory.

## Legacy Boundary

The original `entries.json` is never deleted or migrated in place. `EntryStore` is removed from normal `MINTApp` composition.

An explicit Legacy Library workspace may construct `EntryStore` only after the project session has flushed and torn down its editor/background consumers. Returning to the project workspace flushes and destroys `EntryStore` before the project session reopens. The two owners never exist as active editing runtimes simultaneously and never write each other's formats.

This compatibility path preserves access to folders, characters, narrative decisions, recovery data, and other legacy fields until #111 and #151 provide project-owned equivalents. Its eventual removal is coordinated with #117.

## Failure Semantics

- Project load corruption is visible; it does not create or overwrite user data.
- Autosave failure leaves the project dirty and retryable.
- A failed flush blocks project switching and app termination.
- Creation/import failure or cancellation preserves the prior active project.
- Source archives and immutable document/asset blobs are never garbage-collected by this issue.
- Stale completion, indexing, export, and asset callbacks are discarded by composite identity and generation.
- General mode follows the same storage lifecycle without acquiring Fiction dependencies.

## Verification Contract

Automated coverage must prove:

1. Clean Fiction creation, typing, autosave, quit, and reopen preserve body and selection.
2. The same clean lifecycle works in General mode.
3. Import success, panel cancellation, malformed input, injected write failure, and pre-commit task cancellation preserve the defined owner.
4. A -> B -> A and document switching preserve isolation, including duplicate document UUIDs.
5. Cursor, marked text, Ghost, search jump, and undo state cannot cross a document boundary.
6. Stale background and persistence results cannot publish after a transition.
7. Menu and shortcut actions target the active project.
8. Autosave and termination flush the project session, and save failure prevents unsafe exit.
9. A clean install does not invoke, preload, or download a model.
10. Legacy source and compatibility access survive import cancellation/failure.
11. Project images, Markdown, EPUB, media, and math round-trip through project-scoped assets.
12. The UI smoke fixture verifies the project document body, not `entries.json`.

Final verification includes `swift build`, `swift test`, `swift build --product MINTBench`, `scripts/build-mint-app.sh`, `scripts/smoke-mint-app.sh`, and `scripts/ui-smoke-mint-app.sh` with isolated `CFFIXED_USER_HOME`. Real-editor IME/Ghost/undo smoke is required where automation cannot synthesize a genuine marked-text session.

## Out of Scope

- Mac App Store sandbox/bookmark and distribution proof in #150.
- Full backups, restore UI, version retention, and recovery policy in #151.
- Model installation and recovery UX in #152.
- Deferred Story Intelligence work in #158.
- Broad workspace visual redesign.
- Silent removal or lossy conversion of legacy-only user decisions.
