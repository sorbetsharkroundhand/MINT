# Hierarchical Story Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Formalize MINT's existing Scene → Chapter → Work summary pyramid as project-isolated, incrementally invalidated routing memory with current-manuscript evidence drill-down.

**Architecture:** Add typed scope/version values and pure hierarchy calculations, move derived sidecar access behind an explicit project-or-legacy repository, and bind every BackgroundIndexer load/checkpoint/publication to an immutable scope + generation + document-version identity. Preserve existing summarization prompts and downstream KnowledgeSnapshot behavior while excluding stale hierarchy nodes from the new public routing snapshot.

**Tech Stack:** Swift 6, Foundation, Swift Concurrency, XCTest, Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-09-09-hierarchical-story-memory-design.md`

## Global Constraints

- Project paths use `WritingProjectID` and `WritingDocumentID`, never titles, filenames, or content hashes.
- A `.project` scope never falls back to legacy persistence.
- `SceneContentVersion` is an invalidation key, never a persistent scene or manuscript identity.
- Summaries route retrieval; they do not create facts, warnings, or final evidence.
- Stale hierarchy nodes are omitted from the public routing snapshot.
- Evidence drill-down returns only current-manuscript `EvidenceAnchor` values.
- Sidecar and snapshot publication require matching scope, pass generation, and document version.
- #107 atomic and temporal knowledge types are out of scope.

---

### Task 1: Typed hierarchy, freshness, and evidence drill-down

**Files:**
- Create: `Sources/MINTCore/Knowledge/HierarchicalMemory.swift`
- Modify: `Sources/MINTCore/Knowledge/DocumentOutline.swift`
- Test: `Tests/MINTCoreTests/HierarchicalMemoryTests.swift`

**Interfaces:**
- Produces: `StoryMemoryScope`, `SceneContentVersion`, `StoryMemoryNodeID`, `StoryMemorySnapshot`, and `HierarchicalMemory` pure calculations.
- Consumes: `WritingProjectID`, `WritingDocumentID`, `DocumentOutline`, `KnowledgeSidecar`, and `EvidenceAnchor`.

- [ ] **Step 1: Write failing identity and invalidation tests**

Add tests that construct two chapters with two scenes each, edit one scene, and assert:

```swift
let changes = HierarchicalMemory.changes(previous: previous, outline: edited)
XCTAssertEqual(changes.dirtyScenes.count, 1)
XCTAssertEqual(changes.dirtyChapters, [StoryMemoryNodeID.chapter(path: ["Part One", "Chapter One"])])
XCTAssertTrue(changes.workIsDirty)
XCTAssertFalse(changes.dirtyChapters.contains(.chapter(path: ["Part One", "Chapter Two"])))
```

Also assert that `SceneContentVersion` is the only hierarchy API accepted for scene revisions and that `StoryMemoryScope.project` keeps project/document IDs distinct.

- [ ] **Step 2: Run RED**

Run: `swift test --filter HierarchicalMemoryTests`

Expected: compilation failure because the hierarchy types do not exist.

- [ ] **Step 3: Implement typed values and pure change calculation**

Implement these public contracts:

```swift
public enum StoryMemoryScope: Hashable, Codable, Sendable {
    case project(projectID: WritingProjectID, documentID: WritingDocumentID)
    case legacy(documentID: WritingDocumentID)
}

public struct SceneContentVersion: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
}

public struct StoryMemoryNodeID: Hashable, Codable, Sendable {
    public enum Level: String, Codable, Sendable { case chapter, work }
    public let level: Level
    public let key: String
}

public struct HierarchicalMemoryChanges: Equatable, Sendable {
    public let dirtyScenes: Set<SceneContentVersion>
    public let dirtyChapters: Set<StoryMemoryNodeID>
    public let workIsDirty: Bool
}
```

Add `DocumentOutline.Scene.contentVersion` as a computed typed wrapper. Keep `contentHash` only for current compatibility and document it as a revision digest.

- [ ] **Step 4: Write failing freshness and evidence tests**

Build a sidecar containing one fresh and one stale scene summary plus stale chapter/work hashes. Assert `StoryMemorySnapshot.make(scope:outline:sidecar:body:)` includes only matching nodes. Assert chapter/work drill-down returns current original-text anchors and all returned anchors resolve in the supplied body.

- [ ] **Step 5: Run RED, implement the public snapshot, then run GREEN**

Run: `swift test --filter HierarchicalMemoryTests`

Implement snapshot construction and:

```swift
public func evidence(for nodeID: StoryMemoryNodeID) -> [EvidenceAnchor]
```

Evidence must be created from bounded current scene text, not summary text, and must resolve before inclusion.

Run: `swift test --filter HierarchicalMemoryTests`

Expected: PASS.

- [ ] **Step 6: Commit the hierarchy unit**

```bash
git add Sources/MINTCore/Knowledge/HierarchicalMemory.swift Sources/MINTCore/Knowledge/DocumentOutline.swift Tests/MINTCoreTests/HierarchicalMemoryTests.swift
git commit -m "feat(knowledge): formalize hierarchical memory contracts"
```

### Task 2: Project-scoped and explicit legacy sidecar persistence

**Files:**
- Modify: `Sources/MINTCore/Project/ProjectStore.swift`
- Modify: `Sources/MINTCore/Knowledge/KnowledgeStore.swift`
- Create: `Sources/MINTCore/Knowledge/KnowledgeSidecarRepository.swift`
- Modify: `Tests/MINTCoreTests/ProjectStoreTests.swift`
- Create: `Tests/MINTCoreTests/KnowledgeSidecarRepositoryTests.swift`

**Interfaces:**
- Consumes: `StoryMemoryScope` from Task 1.
- Produces: actor-isolated `KnowledgeSidecarRepository.load(scope:)`, `save(_:pruningTo:scope:)`, `replaceWithFresh(scope:generation:)`, and project-derived data read/write methods.

- [ ] **Step 1: Write failing ProjectStore derived-data tests**

Persist data for two `WritingProjectID` values with the same `WritingDocumentID`. Assert the files are located at:

```text
<root>/<project-a-id>/Intelligence/<document-id>.knowledge.json
<root>/<project-b-id>/Intelligence/<document-id>.knowledge.json
```

Assert reads are isolated and path construction uses only UUID values.

- [ ] **Step 2: Run RED and add the path-safe ProjectStore seam**

Run: `swift test --filter ProjectStoreTests`

Implement actor methods that read/write/remove derived intelligence through `projectURL`, `ProjectPaths`, and `ProjectFileSystem.writeAtomically`. These methods must not mutate `project.json` or user data.

- [ ] **Step 3: Write failing repository isolation and corruption tests**

Use a temporary legacy directory. Save distinct sidecars under `.project` and `.legacy` scopes sharing a document ID. Assert:

- project loads return only project data;
- deleting/corrupting the project file returns a fresh project sidecar instead of legacy data;
- legacy loads continue to use the legacy directory;
- a schema mismatch increments the derived generation without touching manuscript files.

- [ ] **Step 4: Bump the derived schema and implement the repository**

Store `StoryMemoryScope` in `KnowledgeSidecar`, validate requested versus decoded scope, and bump `currentSchemaVersion`. Preserve a computed `entryID` bridge only where current call sites require the raw document UUID.

The repository selects storage with an exhaustive switch:

```swift
switch scope {
case let .project(projectID, documentID):
    // ProjectStore Intelligence path only; never read legacy storage.
case let .legacy(documentID):
    // Explicit legacy directory only.
}
```

- [ ] **Step 5: Run focused and storage regression suites**

Run:

```bash
swift test --filter KnowledgeSidecarRepositoryTests
swift test --filter ProjectStoreTests
swift test --filter LegacyProjectMigrationTests
```

Expected: PASS.

- [ ] **Step 6: Commit persistence**

```bash
git add Sources/MINTCore/Project/ProjectStore.swift Sources/MINTCore/Knowledge/KnowledgeStore.swift Sources/MINTCore/Knowledge/KnowledgeSidecarRepository.swift Tests/MINTCoreTests/ProjectStoreTests.swift Tests/MINTCoreTests/KnowledgeSidecarRepositoryTests.swift
git commit -m "feat(knowledge): isolate sidecars by project and document"
```

### Task 3: Scope/generation/version-owned BackgroundIndexer publication

**Files:**
- Modify: `Sources/MINTCore/Knowledge/BackgroundIndexer.swift`
- Modify: `Tests/MINTCoreTests/IndexerOwnershipTests.swift`
- Modify: `Tests/MINTCoreTests/BackgroundIndexerTests.swift`

**Interfaces:**
- Consumes: `StoryMemoryScope`, `KnowledgeSidecarRepository`, and `StoryMemorySnapshot`.
- Produces: `BackgroundIndexer.attach(store:scopeProvider:)`, immutable `PassIdentity`, guarded hydrate/checkpoint/final publication, and the current hierarchy snapshot.

- [ ] **Step 1: Write failing ownership tests**

Inject a pass identity containing scope, token, and body fingerprint. Assert `canPublish` becomes false for each independent mismatch:

```swift
XCTAssertFalse(indexer.canPublish(identity, currentScope: otherProject))
XCTAssertFalse(indexer.canPublish(identity.withGeneration(identity.generation + 1)))
XCTAssertFalse(indexer.canPublish(identity.withDocumentVersion("changed")))
```

Add a fake repository recorder and assert a late checkpoint/final result after project switch or cancellation performs neither a sidecar commit nor snapshot replacement.

- [ ] **Step 2: Run RED**

Run: `swift test --filter IndexerOwnershipTests`

Expected: compilation/test failure for the new identity and scope-aware publication contract.

- [ ] **Step 3: Implement scope capture and invalidation**

Extend attachment with a MainActor scope provider. If an active project exists but its current document cannot be mapped, return no scope and do not index; never manufacture a legacy scope.

Capture `PassIdentity(scope:generation:documentVersion:)` before detaching. Include the identity in hydrate, checkpoint, metrics, warnings, and final snapshot guards. Add an explicit scope-change invalidation method so project/document changes cancel timers and active work even without a text edit.

- [ ] **Step 4: Route all sidecar access through the repository**

Replace direct `KnowledgeSidecar.load/save/remove/pruneOrphans` calls in pass and hydrate paths. Preserve scene-level checkpoint behavior, but perform each checkpoint only after the exact pass identity is revalidated. Revalidate once more at final sidecar/snapshot publication.

Build `StoryMemorySnapshot` from the current body and attach it to or alongside the existing `KnowledgeSnapshot` without copying event arrays.

- [ ] **Step 5: Use pure hierarchy decisions for propagation**

Replace inline chapter/work dirty comparisons with `HierarchicalMemory` calculations. Keep prompt text and rollup limits unchanged. Only dirty nodes call the summarizer; fresh siblings reuse their existing values.

- [ ] **Step 6: Run indexer and hierarchy suites**

Run:

```bash
swift test --filter IndexerOwnershipTests
swift test --filter BackgroundIndexerTests
swift test --filter HierarchicalMemoryTests
swift test --filter NarrativeIntelligenceTests
swift test --filter SceneSplitTests
```

Expected: PASS.

- [ ] **Step 7: Commit indexer ownership**

```bash
git add Sources/MINTCore/Knowledge/BackgroundIndexer.swift Tests/MINTCoreTests/IndexerOwnershipTests.swift Tests/MINTCoreTests/BackgroundIndexerTests.swift
git commit -m "refactor(knowledge): guard hierarchical memory publication"
```

### Task 4: Runtime wiring, documentation, and complete verification

**Files:**
- Modify: `Sources/MINT/MINTApp.swift`
- Modify: `Sources/MINTCore/ContentView.swift`
- Modify: `PLAN.md`
- Test: `Tests/MINTCoreTests/ContextReportIsolationTests.swift`

**Interfaces:**
- Consumes: scope-aware BackgroundIndexer and the shared `ProjectStore`/`ProjectSession`.
- Produces: project scope in real app sessions, explicit legacy scope in legacy-only tests/previews, and current roadmap evidence.

- [ ] **Step 1: Add runtime scope-selection tests**

Assert an active project maps an entry UUID only to `.project(projectID:documentID:)`; an unmapped entry under an active project returns nil; and no active project maps to `.legacy(documentID:)`.

- [ ] **Step 2: Wire the shared repository and scope provider**

Construct `KnowledgeSidecarRepository` with the app's shared `ProjectStore`, inject it into `BackgroundIndexer`, and provide project/document scope from `ProjectSession`. Observe project and selected-document changes and call the indexer's scope invalidation path.

- [ ] **Step 3: Update the roadmap truthfully**

Mark #103 and #105 complete on main. Mark #106 complete only after all checks pass and the PR is ready; do not close the issue before merge.

- [ ] **Step 4: Run complete verification**

Run:

```bash
swift test
swift build
swift build --product MINTBench
scripts/build-mint-app.sh
scripts/smoke-mint-app.sh
scripts/ui-smoke-mint-app.sh
```

Expected: all commands pass; any existing intentional skip is reported exactly.

- [ ] **Step 5: Review scope and diff**

Confirm no #107 fact/time types, no prompt rewrites, no user-data migration, and no unrelated changes. Run `git diff --check` and verify the main checkout's pre-existing changes remain untouched.

- [ ] **Step 6: Commit and deliver**

```bash
git add Sources/MINT/MINTApp.swift Sources/MINTCore/ContentView.swift PLAN.md Tests/MINTCoreTests/ContextReportIsolationTests.swift docs/superpowers/plans/2026-09-09-hierarchical-story-memory.md
git commit -m "docs(roadmap): record hierarchical memory completion"
git push -u origin codex/106-hierarchical-memory
gh pr create --base main --head codex/106-hierarchical-memory --title "[0.2.0 Story Intelligence] Formalize hierarchical memory" --body "Closes #106"
```

Report each #106 acceptance criterion with the exact production code and test that satisfies it, plus the complete local and GitHub CI results. Leave #106 open until the PR is merged.
