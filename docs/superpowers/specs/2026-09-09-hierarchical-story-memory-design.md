# Hierarchical Story Memory Design

> **Issue:** #106 — Formalize Scene → Chapter → Work hierarchical memory
>
> **Parent contract:** `docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md`

## Goal

Turn the existing Scene/Chapter/Work summary pyramid into an explicit, project-isolated retrieval structure. The implementation preserves current summarization behavior while making invalidation, freshness, persistence scope, evidence drill-down, and publication ownership testable contracts.

This is a derived-memory change only. It does not add atomic `StoryFact`, character/object/relationship state, story time, temporal inference, or continuity judging; those remain in #107 and later issues.

## Chosen migration strategy

Use a transitional dual-path repository:

- a project session stores derived memory under `<project-id>/Intelligence/<document-id>.knowledge.json`;
- a genuine legacy session continues to use the existing global legacy knowledge directory;
- a project-scoped load failure creates an empty project-scoped sidecar and never falls back to legacy data.

`<project-id>` and `<document-id>` are always `WritingProjectID` and `WritingDocumentID` values. Titles, display names, source filenames, and content hashes never participate in the persistence path.

A full editor/storage cutover belongs to #118. An API-only extraction would not satisfy Project A/B isolation, while an immediate full cutover would intrude on #118.

## Identity and version contracts

Introduce an explicit scope value:

```swift
public enum StoryMemoryScope: Hashable, Codable, Sendable {
    case project(projectID: WritingProjectID, documentID: WritingDocumentID)
    case legacy(documentID: WritingDocumentID)
}
```

The enum makes project versus legacy selection exhaustive. There is no optional project ID whose absence could silently trigger a fallback.

Introduce a small `SceneContentVersion` value around the current scene content hash. Hierarchical-memory APIs accept this type rather than an unlabelled `String`. It is an invalidation and memoization key only. It is not a scene identity, manuscript identity, evidence identity, or persistence key.

`WritingProjectID` and `WritingDocumentID` remain the only durable identities used by this task. #106 does not invent a persistent scene UUID. Scene-facing records keep identity and revision separate so a future persistent scene identifier can be added without redefining `SceneContentVersion` or treating a hash as an ID.

## Components

### HierarchicalMemory

Add `Sources/MINTCore/Knowledge/HierarchicalMemory.swift` with pure value types and calculations:

- `StoryMemoryScope` identifies the project/document or genuine legacy document.
- `SceneContentVersion` identifies one version of scene content.
- `StoryMemoryNodeID` identifies chapter and work routing nodes without claiming that a scene revision is a persistent scene ID.
- `StoryMemorySnapshot` contains the scope, current outline, fresh Scene/Chapter/Work summaries, and current-manuscript evidence routes.
- `HierarchicalMemory` groups scenes into chapters, computes child-version digests, reports dirty scene/chapter/work paths, filters stale summaries, and resolves a routing node to current original-text `EvidenceAnchor` values.

The existing `KnowledgeSnapshot` may adapt or expose `StoryMemorySnapshot`; it must not duplicate large event arrays.

### KnowledgeSidecar persistence

Bump the derived sidecar schema and store its exact `StoryMemoryScope`. Loading validates that the decoded scope equals the requested scope.

Project persistence is performed through a path-safe `ProjectStore` derived-data seam under `Intelligence/`. Legacy persistence remains available only through an explicit `.legacy` scope. Project reads and writes never inspect the legacy directory.

Corrupt data, unsupported schemas, and scope mismatches produce a fresh sidecar for the requested scope. This affects only rebuildable derived data and never modifies manuscript documents, project manifests, imported assets, or `UserData`.

### BackgroundIndexer ownership

At pass start, capture one immutable publication identity:

```text
StoryMemoryScope + pass generation + document content version
```

The worker computes a sidecar candidate, snapshot candidate, warnings, and metrics without publishing intermediate sidecars or official snapshots. A serialized final publication gate revalidates all three identity components immediately before committing the sidecar and again before publishing the in-memory snapshot.

Project/document selection changes invalidate and cancel the active pass even when no text edit occurs. A cancelled or late result may be discarded, but it cannot commit to the sidecar or replace the official snapshot. Project-scoped filenames make cross-project overwrite impossible even when two projects contain the same document UUID or identical text.

Foreground Ghost completion continues to read only prepared in-memory snapshots; it performs no sidecar I/O or rebuild work.

## Incremental invalidation

For the current outline:

1. A scene summary is fresh only when its `SceneContentVersion` matches the current scene version.
2. A chapter summary is fresh only when its stored child digest matches the ordered versions of all current child scenes.
3. A work summary is fresh only when its stored child digest matches the ordered fresh chapter nodes, or the documented scene fallback for short works.
4. Changing one scene dirties that scene, its owning chapter, and the work node.
5. Unchanged sibling scene and chapter summaries remain reusable and are not sent to the summarizer again.

Old derived values may remain in an in-progress candidate for memoization, but stale values are excluded from the retrieval/public snapshot. A failed or cancelled rebuild therefore produces silence for that node rather than exposing an outdated route.

## Evidence and truth boundary

Summaries are routing hints, never facts or final evidence. The hierarchy itself does not create warnings from summary differences.

Evidence drill-down starts from a fresh routing node, walks to its current descendant scenes, reads the current in-memory manuscript text, and creates `EvidenceAnchor` values using the stable `WritingDocumentID`, current scene version as a hint, and a bounded quote from original text. An anchor is returned only when it resolves against the current manuscript through the existing resilient source-anchor rules.

Consumers that may create a user-visible claim must use these current original-text anchors. A stale summary, unresolved quote, or scope mismatch yields no evidence and therefore cannot support a warning or continuity judgement.

## Failure and cancellation behavior

- Missing sidecar: start with an empty derived cache in the requested scope.
- Schema corruption or unsupported schema: discard only the derived sidecar and rebuild.
- Project sidecar read failure: do not consult the legacy directory.
- Cancellation, generation change, document switch, or project switch: discard the candidate before persistence and publication.
- Summarizer failure for a dirty node: retain reusable siblings, omit the dirty node from the public snapshot, and retry on a later eligible pass.
- Evidence re-anchoring failure: return no evidence rather than jumping to a hint or summary text.

## Test contract

Add focused tests proving:

1. Editing one scene dirties only that scene, its parent chapter, and the work node.
2. Unchanged sibling scene and chapter summaries are reused.
3. Project A and Project B remain isolated even with identical document IDs and content versions.
4. Project scope never falls back to a legacy sidecar; an explicit legacy session continues to use the legacy path.
5. Stale Scene/Chapter/Work summaries are excluded from retrieval/public snapshots.
6. Evidence drill-down returns only resolvable `EvidenceAnchor` values from the current manuscript.
7. Corrupt or mismatched schemas rebuild derived cache without changing user data.
8. Project/document switch, cancellation, generation mismatch, or content-version mismatch blocks sidecar and snapshot publication.

Run the focused hierarchy and indexer suites, all existing Knowledge/Narrative tests, `swift test`, `swift build`, `swift build --product MINTBench`, app-bundle build, and smoke/UI-smoke scripts.

## Out of scope

- Persistent scene UUID assignment or reconciliation
- Atomic `StoryFact` and domain fact types
- Character, object, relationship, or world-state knowledge
- Story-time ordering and temporal conflict logic
- Structure-first retrieval ranking beyond hierarchy drill-down
- Continuity candidates, Agent Judge, User Canon, or new warning UI
- Full project editor/import cutover owned by #118
