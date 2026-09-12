# Project-Owned Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a verified `WritingProject` the live source of truth from first run through editing, autosave, switching, export, and relaunch, with no model prerequisite and no simultaneous `EntryStore` write owner.

**Architecture:** `ProjectSession` owns the mutable active project/document and delegates verified persistence to the `ProjectStore` actor. UI, editor commands, completion, and indexing consume a composite project/document/generation identity; legacy `EntryStore` is instantiated only inside a mutually exclusive compatibility workspace. Project transitions flush and cancel the old identity before atomically activating and adopting the next verified project.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSTextView`, Swift Package Manager, XCTest, shell UI-smoke scripts.

**Spec:** `docs/superpowers/specs/2026-09-12-project-session-runtime-design.md`

## Global Constraints

- The editor must work on a clean install without model setup, network access, telemetry, or an automatic model download.
- `ProjectSession` is the only mutable runtime owner of the active `WritingProject`; normal project UI must not construct or mutate `EntryStore`.
- Generic project/storage code must not depend on Fiction-specific types.
- Never migrate or modify legacy `entries.json` in place; import failure or cancellation preserves the source and the previously active project.
- Reject path traversal and symlink escape; no cleanup in this plan may remove immutable manuscript, asset, or UserData files.
- Project/document changes invalidate Ghost, completion, indexing, cursor state, and undo by composite project/document identity before new work starts.
- Preserve Hangul marked text, Ghost Tab/right-arrow/Escape, native within-document undo, cursor highlight, Markdown/EPUB/media/math round-trip, and foreground prediction priority.
- Derived Intelligence remains rebuildable and cannot mutate manuscripts or user decisions.
- #150 owns Store sandbox/bookmark proof, #151 owns full recovery/retention, #152 owns model-install recovery, and #158 remains deferred.
- All new behavior follows strict red-green-refactor; never weaken or rewrite an existing assertion just to make the suite pass.

---

### Task 1: Persist Non-Destructive Document State and Atomic Activation

**Files:**
- Modify: `Sources/MINTCore/Project/WritingProject.swift`
- Modify: `Sources/MINTCore/Project/ProjectManifest.swift`
- Modify: `Sources/MINTCore/Project/ProjectStore.swift`
- Modify: `Sources/MINTCore/Project/LegacyProjectMigrator.swift`
- Modify: `Tests/MINTCoreTests/WritingProjectTests.swift`
- Modify: `Tests/MINTCoreTests/ProjectStoreTests.swift`
- Modify: `Tests/MINTCoreTests/LegacyProjectMigrationTests.swift`

**Interfaces:**
- Produces: `WritingProject.trashedDocumentIDs: Set<WritingDocumentID>` with missing-key decode defaulting to `[]`.
- Produces: `ProjectStore.activateAndLoad(id:) throws -> WritingProject`.
- Produces: `ProjectStore.prepareLegacyMigration(from:mode:title:) throws -> LegacyMigrationResult` that never changes `active-project.json`.
- Preserves: `ProjectStore.migrateLegacy(from:mode:title:)` as the compatibility prepare-plus-activate API.

- [ ] **Step 1: Write failing backwards-compatibility and trash round-trip tests**

```swift
func testMissingTrashFieldDecodesAsEmptyAndRoundTripsTrash() throws {
    let document = WritingDocument(id: WritingDocumentID(), title: "Draft", body: "body", kind: .manuscript)
    let legacyJSON = """
    {"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"title":"Old","mode":"general","documents":[]}
    """
    let decoded = try JSONDecoder().decode(WritingProject.self, from: Data(legacyJSON.utf8))
    XCTAssertEqual(decoded.trashedDocumentIDs, [])

    let project = WritingProject(id: WritingProjectID(), title: "New", mode: .general,
        documents: [document], trashedDocumentIDs: [document.id])
    XCTAssertEqual(try JSONDecoder().decode(WritingProject.self,
        from: JSONEncoder().encode(project)), project)
}
```

- [ ] **Step 2: Run the model test and confirm RED**

Run: `swift test --filter WritingProjectTests/testMissingTrashFieldDecodesAsEmptyAndRoundTripsTrash`

Expected: compile failure because `trashedDocumentIDs` and the initializer argument do not exist.

- [ ] **Step 3: Add backwards-compatible project and manifest fields**

Implement custom `Codable` in `WritingProject` and `ProjectManifest` so missing `trashedDocumentIDs` decodes as an empty set. Reject trash IDs not present in `documents` while reading/saving a manifest. Keep schema version `1` because the new key is optional and older data stays readable.

```swift
public var trashedDocumentIDs: Set<WritingDocumentID>

public init(
    id: WritingProjectID,
    title: String,
    mode: WritingMode,
    documents: [WritingDocument],
    trashedDocumentIDs: Set<WritingDocumentID> = []
) { ... }
```

- [ ] **Step 4: Run WritingProject and ProjectStore tests and confirm GREEN**

Run: `swift test --filter 'WritingProjectTests|ProjectStoreTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Write failing atomic-activation and prepared-import tests**

```swift
func testActivateAndLoadReturnsExactlyTheDurableActiveProject() async throws {
    let store = ProjectStore(root: try temporaryProjectRoot())
    let project = projectFixture()
    try await store.save(project)
    let activated = try await store.activateAndLoad(id: project.id)
    let durable = try await store.activeProject()
    XCTAssertEqual(activated, project)
    XCTAssertEqual(durable, project)
}

func testPreparedMigrationDoesNotReplaceActiveProject() async throws {
    let original = projectFixture()
    try await store.save(original)
    try await store.activate(id: original.id)
    let prepared = try await store.prepareLegacyMigration(
        from: source, mode: .fiction, title: "Imported")
    let active = try await store.activeProject()
    XCTAssertNotEqual(prepared.projectID, original.id)
    XCTAssertEqual(active, original)
}
```

- [ ] **Step 6: Run the store tests and confirm RED**

Run: `swift test --filter 'ProjectStoreTests/testActivateAndLoadReturnsExactlyTheDurableActiveProject|LegacyProjectMigrationTests/testPreparedMigrationDoesNotReplaceActiveProject'`

Expected: compile failure because both APIs are absent.

- [ ] **Step 7: Implement one-lock activation and split migration preparation**

`activateAndLoad` must verify the project, atomically write `active-project.json`, and return the verified value inside one `withStoreLock` call. It must not check cancellation after the marker write. Move candidate creation, source revalidation, receipt writing, and verification into `prepareLegacyMigration`; keep activation out of that method. Implement `migrateLegacy` by preparing and then calling `activateAndLoad` for compatibility.

- [ ] **Step 8: Run migration/store tests and confirm GREEN**

Run: `swift test --filter 'WritingProjectTests|ProjectStoreTests|LegacyProjectMigrationTests'`

Expected: all selected tests pass, including prior source/asset preservation checks.

- [ ] **Step 9: Commit Task 1**

```bash
git add Sources/MINTCore/Project Tests/MINTCoreTests/WritingProjectTests.swift Tests/MINTCoreTests/ProjectStoreTests.swift Tests/MINTCoreTests/LegacyProjectMigrationTests.swift
git commit -m "feat(project): add atomic activation and durable trash"
```

### Task 2: Make ProjectSession the Authoritative Mutable Runtime

**Files:**
- Create: `Sources/MINTCore/Project/ProjectRuntimeIdentity.swift`
- Modify: `Sources/MINTCore/Project/ProjectSession.swift`
- Modify: `Tests/MINTCoreTests/ProjectSessionTests.swift`

**Interfaces:**
- Consumes: `ProjectStore.activateAndLoad(id:)` from Task 1.
- Produces: stable `ProjectDocumentKey(projectID:documentID:)` and `ProjectRuntimeIdentity(key:generation:)`.
- Produces: `ProjectSessionPhase` (`loading`, `needsProject`, `ready`, `suspended`, `failed`), `ProjectSavePhase`, `runtimeIdentity`, `RecentProjectSummary`, `recentProjects`, and `lastErrorMessage`.
- Produces mutation methods `updateSelectedDocumentBody(_:)`, `renameSelectedDocument(to:)`, `createDocument(title:kind:)`, `trashSelectedDocument()`, and `restoreDocument(_:)`.
- Produces lifecycle methods `bootstrap()`, `flush()`, `activateProject(id:)`, and `saveAndActivate(_:)`.
- Produces callbacks `willTransition: (() -> Void)?` and `documentDidChange: ((ProjectRuntimeIdentity) -> Void)?`.

- [ ] **Step 1: Write failing body mutation and autosave tests**

```swift
func testBodyMutationUpdatesSelectedProjectDocumentAndFlushesToStore() async throws {
    let store = ProjectStore(root: root)
    let project = fictionProject()
    try await store.save(project)
    try await store.activate(id: project.id)
    let session = ProjectSession(store: store, defaults: defaults, autosaveDelay: .seconds(60))
    try await session.bootstrap()

    session.updateSelectedDocumentBody("edited")
    XCTAssertEqual(session.selectedDocument?.body, "edited")
    XCTAssertEqual(session.savePhase, .dirty)
    try await session.flush()

    let reopened = try await store.load(id: project.id)
    XCTAssertEqual(reopened.documents[0].body, "edited")
    XCTAssertEqual(session.savePhase, .saved)
}
```

Name the protected break: routing editor text anywhere except the selected document, or clearing dirty state before verified persistence, must fail this test.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter ProjectSessionTests/testBodyMutationUpdatesSelectedProjectDocumentAndFlushesToStore`

Expected: compile failure for the new initializer and mutation/save APIs.

- [ ] **Step 3: Implement runtime identity, mutation, dirty generation, and flush**

Use a `Task<Void, Never>?` only for the debounce timer. Each save captures a value snapshot and generation. Clear dirty state only when the persisted generation still matches; otherwise loop in explicit `flush()` until the latest generation is durable. Cancellation of an obsolete timer is not a user-visible save failure.

```swift
public struct ProjectDocumentKey: Hashable, Codable, Sendable {
    public let projectID: WritingProjectID
    public let documentID: WritingDocumentID
}

public struct ProjectRuntimeIdentity: Hashable, Sendable {
    public let key: ProjectDocumentKey
    public let generation: UInt64
}
```

- [ ] **Step 4: Run the new test and all session tests and confirm GREEN**

Run: `swift test --filter ProjectSessionTests`

Expected: all session tests pass.

- [ ] **Step 5: Write failing selection persistence, trash, and switch-failure tests**

```swift
func testSelectionPersistsAcrossNewSessionForSameProject() async throws {
    let first = ProjectSession(store: store, defaults: defaults)
    try await first.activateProject(id: project.id)
    first.selectDocument(project.documents[1].id)
    let second = ProjectSession(store: store, defaults: defaults)
    try await second.bootstrap()
    XCTAssertEqual(second.selectedDocumentID, project.documents[1].id)
}

func testFailedFlushDoesNotSwitchOrChangeDurableActiveProject() async throws {
    session.updateSelectedDocumentBody("dirty")
    do { try await session.activateProject(id: other.id); XCTFail() } catch {}
    let durable = try await reliableStore.activeProject()
    XCTAssertEqual(session.activeProject?.id, original.id)
    XCTAssertEqual(durable?.id, original.id)
}

func testTrashingSelectedDocumentKeepsBytesAndSelectsVisibleReplacement() async throws {
    let removed = try XCTUnwrap(session.selectedDocumentID)
    session.trashSelectedDocument()
    XCTAssertTrue(session.activeProject?.trashedDocumentIDs.contains(removed) == true)
    XCTAssertNotEqual(session.selectedDocumentID, removed)
    try await session.flush()
    let reopened = try await store.load(id: project.id)
    XCTAssertTrue(reopened.documents.contains { $0.id == removed })
}
```

- [ ] **Step 6: Run the three tests and confirm RED**

Run: `swift test --filter 'ProjectSessionTests/(testSelectionPersistsAcrossNewSessionForSameProject|testFailedFlushDoesNotSwitchOrChangeDurableActiveProject|testTrashingSelectedDocumentKeepsBytesAndSelectsVisibleReplacement)'`

Expected: selection is currently memory-only; mutation/trash/flush APIs are missing.

- [ ] **Step 7: Implement persisted selection, recents, non-destructive document CRUD, and transitions**

Persist selected document under `mint.selectedDocument.<project UUID>` and recent IDs under `mint.recentProjects`. Resolve `RecentProjectSummary(id:title:mode:)` only from projects that `ProjectStore.load` verifies; preserve an invalid ID in preferences for recovery, but omit it from the picker and publish its error without replacing the active project. Invoke `willTransition` before flushing. Use `activateAndLoad` and adopt its returned value without a post-activation cancellation check. Increment generation for document selection and all content mutations.

- [ ] **Step 8: Run session/store tests and confirm GREEN**

Run: `swift test --filter 'ProjectSessionTests|ProjectStoreTests'`

Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 2**

```bash
git add Sources/MINTCore/Project/ProjectRuntimeIdentity.swift Sources/MINTCore/Project/ProjectSession.swift Tests/MINTCoreTests/ProjectSessionTests.swift
git commit -m "feat(project): make session own active document edits"
```

### Task 3: Make Creation and Import Preserve the Current Owner

**Files:**
- Modify: `Sources/MINTCore/Onboarding/ProjectCreationCoordinator.swift`
- Modify: `Sources/MINTCore/Onboarding/ImportProjectCoordinator.swift`
- Modify: `Tests/MINTCoreTests/ImportProjectCoordinatorTests.swift`
- Modify: `Tests/MINTCoreTests/FirstRunStateTests.swift`

**Interfaces:**
- Consumes: session transitions and prepared migration from Tasks 1–2.
- Produces: creation/import that cannot publish an unverified or pre-commit candidate.

- [ ] **Step 1: Write failing cancelled-import ownership test**

```swift
func testCancelledPreparedImportLeavesCurrentSessionAndMarkerUntouched() async throws {
    let current = try await ProjectCreationCoordinator(session: session)
        .createProject(title: "Current", mode: .general)
    let coordinator = ImportProjectCoordinator(
        store: store,
        session: session,
        cancellationCheckpoint: { throw CancellationError() })

    do { _ = try await coordinator.importLegacy(from: source, mode: .fiction, title: "Import"); XCTFail() }
    catch is CancellationError {}

    let durable = try await store.activeProject()
    XCTAssertEqual(session.activeProject?.id, current.projectID)
    XCTAssertEqual(durable?.id, current.projectID)
    XCTAssertEqual(try Data(contentsOf: source), originalSource)
}
```

The production initializer defaults `cancellationCheckpoint` to `Task.checkCancellation`. The injected closure makes the exact prepare/commit boundary deterministic without adding a test-only method to production.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter ImportProjectCoordinatorTests/testCancelledPreparedImportLeavesCurrentSessionAndMarkerUntouched`

Expected: the current migrator activates before the coordinator cancellation check.

- [ ] **Step 3: Route import through prepare, checkpoint, and session activation**

```swift
let result = try await store.prepareLegacyMigration(from: sourceURL, mode: mode, title: title)
try await cancellationCheckpoint()
try await session.activateProject(id: result.projectID)
return result
```

Creation remains a session `saveAndActivate` transaction and therefore flushes the prior project before publishing the new one.

- [ ] **Step 4: Run onboarding/migration tests and confirm GREEN**

Run: `swift test --filter 'ImportProjectCoordinatorTests|LegacyProjectMigrationTests|FirstRunStateTests'`

Expected: success, malformed failure, source preservation, and cancellation all pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/MINTCore/Onboarding Tests/MINTCoreTests/ImportProjectCoordinatorTests.swift Tests/MINTCoreTests/FirstRunStateTests.swift
git commit -m "fix(onboarding): commit imports after cancellation gate"
```

### Task 4: Introduce Project-Scoped Editor Identity and Position State

**Files:**
- Create: `Sources/MINTCore/Editor/EditorSearchJump.swift`
- Modify: `Sources/MINTCore/Storage/WritingPositionStore.swift`
- Modify: `Sources/MINTCore/Editor/BlockTextView.swift`
- Modify: `Tests/MINTCoreTests/WritingPositionTests.swift`
- Modify: `Tests/MINTCoreTests/SerializationTests.swift`
- Modify: `Tests/MINTCoreTests/EntryStoreUndoContractTests.swift`

**Interfaces:**
- Consumes: stable `ProjectDocumentKey` from Task 2.
- Produces: `EditorDocumentIdentity.project(ProjectDocumentKey)` and `.legacy(UUID)`; body-generation changes do not trigger editor document reloads.
- Produces: neutral `EditorSearchJump(documentID:query:sequence:)`.
- Produces: composite position lookup/record methods while retaining UUID-only legacy methods.

- [ ] **Step 1: Write failing duplicate-UUID position isolation test**

```swift
func testSameDocumentUUIDInDifferentProjectsKeepsSeparatePositions() throws {
    let documentID = WritingDocumentID(rawValue: UUID())
    let a = ProjectDocumentKey(projectID: WritingProjectID(), documentID: documentID)
    let b = ProjectDocumentKey(projectID: WritingProjectID(), documentID: documentID)
    store.record(location: 4, selectionLength: 0, body: "AAAA", for: a)
    store.record(location: 9, selectionLength: 0, body: "BBBBBBBBB", for: b)
    XCTAssertEqual(store.restore(in: "AAAA", for: a)?.location, 4)
    XCTAssertEqual(store.restore(in: "BBBBBBBBB", for: b)?.location, 9)
}
```

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter WritingPositionTests/testSameDocumentUUIDInDifferentProjectsKeepsSeparatePositions`

Expected: compile failure because `ProjectDocumentKey` and composite overloads are absent.

- [ ] **Step 3: Add composite keys with legacy decode fallback**

Encode new records under `project UUID/document UUID`. Keep decoding existing UUID-only dictionaries and consult them only when no composite record exists. Never rewrite or discard a legacy position merely by reading it.

- [ ] **Step 4: Run position tests and confirm GREEN**

Run: `swift test --filter WritingPositionTests`

Expected: all position tests pass.

- [ ] **Step 5: Write failing editor identity-boundary tests**

```swift
@MainActor
func testProjectIdentityChangeClearsUndoAndGhost() throws {
    let textView = makeBlockTextViewForTesting()
    textView.load(markdown: "A")
    textView.ghostText = "old suggestion"
    textView.undoManager?.registerUndo(withTarget: textView) { target in
        target.string = "A from old undo"
    }

    textView.prepareForDocumentTransition(markdown: "B")

    XCTAssertEqual(textView.string, "B")
    XCTAssertNil(textView.ghostSnapshotForAccessibility())
    XCTAssertFalse(textView.undoManager?.canUndo == true)
}
```

Use the same TextKit construction already used by serialization tests for `makeBlockTextViewForTesting`. Keep the existing IME serialization tests as the marked-text contract; the production change that must fail this test is retaining old undo or Ghost state when the stable project/document key changes.

- [ ] **Step 6: Run and confirm RED**

Run: `swift test --filter 'EntryStoreUndoContractTests|SerializationTests/testProjectIdentityChangeClearsUndoAndGhost'`

Expected: old identity is only a UUID and undo history remains attached across loads.

- [ ] **Step 7: Generalize editor input and enforce identity transitions**

Replace `entryID` with `EditorDocumentIdentity` in `MintBlockEditor`. Replace `EntryStore.SearchJump` with `EditorSearchJump`. On identity change, unmark text, persist the old composite position, clear suggestion/dialog state, discard stale callbacks, load the new body, and call `undoManager?.removeAllActions()` only for a true identity change.

- [ ] **Step 8: Run editor, IME, Ghost, and position tests and confirm GREEN**

Run: `swift test --filter 'WritingPositionTests|SerializationTests|EntryStoreUndoContractTests|GhostAccessibilityTests'`

Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 4**

```bash
git add Sources/MINTCore/Editor Sources/MINTCore/Storage/WritingPositionStore.swift Tests/MINTCoreTests/WritingPositionTests.swift Tests/MINTCoreTests/SerializationTests.swift Tests/MINTCoreTests/EntryStoreUndoContractTests.swift
git commit -m "feat(editor): isolate project document transitions"
```

### Task 5: Cut the Workspace, Navigator, Search, and Commands to ProjectSession

**Files:**
- Create: `Sources/MINTCore/Workspace/ProjectSearch.swift`
- Modify: `Sources/MINTCore/Workspace/ProjectNavigatorView.swift`
- Modify: `Sources/MINTCore/Workspace/WorkspaceShellView.swift`
- Modify: `Sources/MINTCore/ContentView.swift`
- Modify: `Sources/MINTCore/AppCommands.swift`
- Modify: `Sources/MINT/MINTApp.swift`
- Create: `Tests/MINTCoreTests/ProjectSearchTests.swift`
- Create: `Tests/MINTCoreTests/ProjectCommandRoutingTests.swift`
- Modify: `Tests/MINTCoreTests/WorkspaceShellModeTests.swift`

**Interfaces:**
- Consumes: authoritative session and neutral editor identity from Tasks 2 and 4.
- Produces: `ProjectSearchResult(projectID:documentID:title:snippet:query:)` and deterministic in-memory search.
- Produces: `ProjectCommandActions` closures used by `MintCommands`, testable without invoking panels.
- Produces: a verified recent-project picker plus in-workspace New Project and Import Legacy Library actions.

- [ ] **Step 1: Write failing active-project search and command-routing tests**

```swift
func testSearchReturnsOnlyActiveProjectDocumentsAndSelectionTargetsResult() async throws {
    let results = ProjectSearch.results(query: "needle", in: projectA)
    XCTAssertEqual(results.map(\.documentID), [projectA.documents[1].id])
    XCTAssertFalse(results.contains { $0.projectID == projectB.id })
}

func testNewDocumentCommandMutatesTheActiveSessionProject() async throws {
    let before = session.activeProject?.documents.count
    ProjectCommandActions(session: session).newDocument(.manuscript)
    XCTAssertEqual(session.activeProject?.documents.count, before.map { $0 + 1 })
}

func testRecentProjectPickerRejectsMissingProjectWithoutLeavingCurrent() async throws {
    let currentID = session.activeProject?.id
    do { try await session.activateProject(id: missingID); XCTFail() } catch {}
    XCTAssertEqual(session.activeProject?.id, currentID)
}
```

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter 'ProjectSearchTests|ProjectCommandRoutingTests'`

Expected: new search/action types are absent.

- [ ] **Step 3: Implement deterministic project search and command actions**

Search a copied `[WritingDocument]` snapshot, preserve document order, and derive literal snippets around the first case-insensitive match. Command closures call session methods; panel presentation remains in `MintCommands`.

- [ ] **Step 4: Run search/command tests and confirm GREEN**

Run: `swift test --filter 'ProjectSearchTests|ProjectCommandRoutingTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Replace project-workspace EntryStore dependencies**

Make `ContentView`, `WorkspaceSurface`, `EditorPane`, toolbar, status bar, `ProjectNavigatorView`, and `MintCommands` observe `ProjectSession`. Bind editor text to `session.selectedDocument?.body` and `updateSelectedDocumentBody`. Show documents from `activeProject.documents` excluding trash IDs. Route search result selection through `selectDocument` and then issue `EditorSearchJump`. Add a recent-project menu that displays titles from verified session recents; failed verification leaves the current project selected and surfaces the error.

Add File-menu actions for New Fiction Project, New General Project, and Import Legacy Library. They present the same creation/import flows used by First Run; command code does not duplicate storage or migration logic.

Keep Fiction-only panels behind existing workspace routing. Where those panels still require `JournalEntry` decisions, show their existing empty/unavailable state rather than create an EntryStore mirror.

- [ ] **Step 6: Remove normal EntryStore construction and compile**

Delete `@StateObject private var store = EntryStore()` from `MINTApp`. Construct `ProjectSession` once and pass it to commands/content. Do not delete `EntryStore.swift` or compatibility tests.

Run: `swift build`

Expected: build succeeds with no normal project view initializer requiring `EntryStore`.

- [ ] **Step 7: Run workspace and project tests**

Run: `swift test --filter 'ProjectSessionTests|ProjectSearchTests|ProjectCommandRoutingTests|WorkspaceShellModeTests'`

Expected: all selected tests pass.

- [ ] **Step 8: Commit Task 5**

```bash
git add Sources/MINT Sources/MINTCore/ContentView.swift Sources/MINTCore/AppCommands.swift Sources/MINTCore/Workspace Tests/MINTCoreTests
git commit -m "feat(workspace): edit the active project session"
```

### Task 6: Connect First Run and Enforce Explicit Completion Authorization

**Files:**
- Create: `Sources/MINTCore/Onboarding/FirstRunView.swift`
- Modify: `Sources/MINTCore/ContentView.swift`
- Modify: `Sources/MINTCore/Settings.swift`
- Modify: `Sources/MINTCore/Editor/CompletionController.swift`
- Modify: `Tests/MINTCoreTests/FirstRunStateTests.swift`
- Modify: `Tests/MINTCoreTests/CompletionIntentTests.swift`
- Modify: `Tests/MINTCoreTests/SmokeConfigurationTests.swift`

**Interfaces:**
- Consumes: session `bootstrap`, creation, and import coordinators.
- Produces: first-run project choice and explicit `CompletionAuthorization` migration.

- [ ] **Step 1: Write failing clean-install no-model tests**

```swift
func testUnconfirmedInstallStartsWithCompletionDisabled() {
    defaults.removePersistentDomain(forName: suite)
    let settings = CompletionSettings(defaults: defaults)
    XCTAssertFalse(settings.autocompleteEnabled)
    XCTAssertEqual(settings.authorization, .unconfigured)
}

func testPreloadStaysIdleWhenCompletionIsUnconfigured() {
    let controller = CompletionController(settings: unconfiguredSettings)
    controller.preloadEngine()
    XCTAssertEqual(controller.engineState, .idle)
}
```

`preloadEngine` changes `engineState` to `.downloading(0)` synchronously before it starts engine work, so the `.idle` assertion proves the real controller returned at its authorization gate without starting a download task.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter 'CompletionIntentTests/testUnconfirmedInstallStartsWithCompletionDisabled|CompletionIntentTests/testPreloadStaysIdleWhenCompletionIsUnconfigured'`

Expected: current defaults enable autocomplete and no explicit authorization exists.

- [ ] **Step 3: Implement authorization migration and controller gates**

Add `CompletionAuthorization: String, Codable` with `.unconfigured`, `.disabled`, and `.enabled`. Map existing `initialModelConfirmed == true` plus `autocompleteEnabled` to enabled/disabled. Missing or unconfirmed state becomes `.unconfigured` with autocomplete false. `preloadEngine`, completion scheduling, and settings enablement all require `.enabled`; an explicit Settings toggle sets enabled or disabled.

- [ ] **Step 4: Run completion/smoke configuration tests and confirm GREEN**

Run: `swift test --filter 'CompletionIntentTests|SmokeConfigurationTests'`

Expected: all selected tests pass after updating the obsolete smoke expectation from “after model choice” to clean offline project startup.

- [ ] **Step 5: Connect the bootstrap phases to FirstRunView**

Render `FirstRunView` only for `.needsProject`; render the project workspace only for `.ready`; render progress/error for the other phases. Provide Fiction/General create buttons and an `NSOpenPanel` legacy-import action. Panel cancellation performs no coordinator call. Remove `InitialModelPicker` presentation from `ContentView`; model controls remain in Settings.

- [ ] **Step 6: Run onboarding and build verification**

Run: `swift test --filter 'FirstRunStateTests|ImportProjectCoordinatorTests|CompletionIntentTests|SmokeConfigurationTests'`

Run: `swift build`

Expected: tests and build pass.

- [ ] **Step 7: Commit Task 6**

```bash
git add Sources/MINTCore/Onboarding Sources/MINTCore/ContentView.swift Sources/MINTCore/Settings.swift Sources/MINTCore/Editor/CompletionController.swift Tests/MINTCoreTests
git commit -m "feat(onboarding): open a project without model setup"
```

### Task 7: Feed Completion and Indexing Project-Owned Snapshots

**Files:**
- Create: `Sources/MINTCore/Project/ProjectDocumentSnapshot.swift`
- Modify: `Sources/MINTCore/Project/ProjectSession.swift`
- Modify: `Sources/MINTCore/Editor/CompletionController.swift`
- Modify: `Sources/MINTCore/Knowledge/BackgroundIndexer.swift`
- Modify: `Sources/MINTCore/ContentView.swift`
- Modify: `Tests/MINTCoreTests/ContextReportIsolationTests.swift`
- Modify: `Tests/MINTCoreTests/IndexerOwnershipTests.swift`

**Interfaces:**
- Produces: `ProjectDocumentSnapshot(identity:title:body:kind:)` from the selected session document.
- Changes indexer attachment to `attach(documentProvider:)` where the closure returns that immutable snapshot.
- Retains an explicitly named `attachLegacy(store:)` only for the legacy compatibility workspace.

- [ ] **Step 1: Write failing duplicate-document-UUID stale-publication tests**

```swift
func testABAReturnWithSameDocumentUUIDRejectsOriginalAResult() async throws {
    let documentID = WritingDocumentID(rawValue: UUID())
    let aKey = ProjectDocumentKey(projectID: WritingProjectID(), documentID: documentID)
    let bKey = ProjectDocumentKey(projectID: WritingProjectID(), documentID: documentID)
    let a1 = ProjectRuntimeIdentity(key: aKey, generation: 1)
    let b = ProjectRuntimeIdentity(key: bKey, generation: 2)
    let a2 = ProjectRuntimeIdentity(key: aKey, generation: 3)
    indexer.noteScopeChange(to: a1)
    let oldPass = indexer.beginPassForTesting()
    indexer.noteScopeChange(to: b)
    indexer.noteScopeChange(to: a2)
    let committed = await indexer.commitForTesting(oldPass)
    XCTAssertFalse(committed)
}
```

Add the analogous completion report test: a report captured under A generation 1 cannot appear under A generation 3.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter 'IndexerOwnershipTests/testABAReturnWithSameDocumentUUIDRejectsOriginalAResult|ContextReportIsolationTests/testABAReturnRejectsOriginalContext'`

Expected: current public switching is UUID-based and the indexer reads EntryStore.

- [ ] **Step 3: Introduce immutable snapshots and refactor provider reads**

All indexer reads of `store.activeEntry`, `store.entries`, and mutable body state become reads from the captured `ProjectDocumentSnapshot`. Derived candidate persistence to legacy entry metadata is disabled in the project path; sidecar persistence remains project-scoped. Existing token/body/scope guards gain the session generation from `ProjectRuntimeIdentity`.

- [ ] **Step 4: Wire session callbacks before publishing new identity**

Set `session.willTransition` to unmark current text, call completion invalidation, and call indexer scope cancellation. Set `session.documentDidChange` to notify completion/indexer using the new snapshot. Background consumers never call session mutation APIs.

- [ ] **Step 5: Run background/completion tests and confirm GREEN**

Run: `swift test --filter 'BackgroundIndexerTests|IndexerOwnershipTests|ContextReportIsolationTests|CompletionIntentTests'`

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 7**

```bash
git add Sources/MINTCore/Project Sources/MINTCore/Editor/CompletionController.swift Sources/MINTCore/Knowledge/BackgroundIndexer.swift Sources/MINTCore/ContentView.swift Tests/MINTCoreTests
git commit -m "refactor(knowledge): consume project document snapshots"
```

### Task 8: Add Project-Scoped Asset Access and Export

**Files:**
- Create: `Sources/MINTCore/Project/ProjectAssetAccess.swift`
- Modify: `Sources/MINTCore/Project/ProjectManifest.swift`
- Modify: `Sources/MINTCore/Project/ProjectStore.swift`
- Modify: `Sources/MINTCore/Project/ProjectSession.swift`
- Modify: `Sources/MINTCore/Storage/ImageStore.swift`
- Modify: `Sources/MINTCore/Editor/BlockTextView.swift`
- Modify: `Sources/MINTCore/Export/MarkdownExporter.swift`
- Modify: `Sources/MINTCore/Export/EpubExporter.swift`
- Modify: `Tests/MINTCoreTests/ProjectStoreTests.swift`
- Modify: `Tests/MINTCoreTests/ImageStoreGCTests.swift`
- Modify: `Tests/MINTCoreTests/MarkdownExporterTests.swift`
- Modify: `Tests/MINTCoreTests/BackgroundExportSearchTests.swift`
- Modify: `Tests/MINTCoreTests/MathRoundTripTests.swift`

**Interfaces:**
- Produces: immutable `ProjectAssetCatalog` with synchronous `data(for:) -> Data?`, built from bytes verified by `ProjectStore` for one project ID.
- Produces: `ProjectStore.assetCatalog(id:) throws -> ProjectAssetCatalog`.
- Produces: `ProjectStore.addAsset(_:reference:to:) throws` with verified immutable bytes and atomic manifest update.
- Produces: session `importAsset(data:reference:for:) async throws -> String` guarded by initiating runtime identity.
- Produces: `ProjectSessionError.staleRuntime` when an asynchronous result no longer owns the active generation.

- [ ] **Step 1: Write failing asset persistence and stale-insertion tests**

```swift
func testAddAssetPersistsVerifiedBytesAndRetainsExistingDocuments() async throws {
    try await store.save(project)
    try await store.addAsset(Data([1, 2, 3]), reference: "images/a.png", to: project.id)
    let asset = try await store.assetData(reference: "images/a.png", in: project.id)
    let reopened = try await store.load(id: project.id)
    XCTAssertEqual(asset, Data([1, 2, 3]))
    XCTAssertEqual(reopened, project)
}

func testAssetResultForOldRuntimeDoesNotInsertMarkerIntoNewDocument() async throws {
    let identity = try XCTUnwrap(session.runtimeIdentity)
    session.selectDocument(otherDocumentID)
    do { _ = try await session.importAsset(data: bytes, reference: "images/a.png", for: identity); XCTFail() }
    catch ProjectSessionError.staleRuntime {}
    XCTAssertFalse(session.selectedDocument?.body.contains("images/a.png") == true)
}
```

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter 'ProjectStoreTests/testAddAssetPersistsVerifiedBytesAndRetainsExistingDocuments|ProjectSessionTests/testAssetResultForOldRuntimeDoesNotInsertMarkerIntoNewDocument'`

Expected: asset mutation APIs are absent.

- [ ] **Step 3: Implement verified asset writes and immutable catalogs**

Validate references with `ProjectPaths.validateRelative`. Write the content-addressed asset before replacing the manifest. Replacing an existing reference with different bytes creates a new immutable blob and atomically updates only its manifest record. Never delete the old blob. Build `ProjectAssetCatalog` inside the store actor by calling `verified` for every asset; the editor and synchronous exporters receive only this value snapshot and never read paths directly.

- [ ] **Step 4: Run store/session tests and confirm GREEN**

Run: `swift test --filter 'ProjectStoreTests|ProjectSessionTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Write failing project Markdown/EPUB/media round-trip tests**

Export a `WritingDocument` containing `![그림](images/a.png){width=60}` and inline/block math through a project resolver. Assert literal Markdown preservation, copied image bytes, EPUB inclusion, and unchanged math source. Use hand-authored expected strings and bytes.

- [ ] **Step 6: Run and confirm RED**

Run: `swift test --filter 'MarkdownExporterTests/testProjectResolverExportsImageBytes|BackgroundExportSearchTests/testProjectEpubIncludesResolvedAsset|MathRoundTripTests/testProjectExportPreservesMathSource'`

Expected: exporters currently accept `JournalEntry` and global `MintImageStore` only.

- [ ] **Step 7: Add project exporter overloads and editor resolver injection**

Keep legacy exporter APIs for compatibility tests. Pass an immutable catalog into `MintBlockEditor`; do not mutate `MintImageStore` global roots during project switches. Persist bytes before inserting an image marker and recheck runtime identity on completion.

- [ ] **Step 8: Run export/media/editor tests and confirm GREEN**

Run: `swift test --filter 'ProjectStoreTests|ImageStoreGCTests|MarkdownExporterTests|BackgroundExportSearchTests|MathRoundTripTests|SerializationTests'`

Expected: all selected tests pass.

- [ ] **Step 9: Commit Task 8**

```bash
git add Sources/MINTCore/Project Sources/MINTCore/Storage/ImageStore.swift Sources/MINTCore/Editor/BlockTextView.swift Sources/MINTCore/Export Tests/MINTCoreTests
git commit -m "feat(project): scope assets and exports to projects"
```

### Task 9: Add the Mutually Exclusive Legacy Boundary and Safe Shutdown

**Files:**
- Create: `Sources/MINTCore/Legacy/LegacyWorkspaceController.swift`
- Create: `Sources/MINTCore/Legacy/LegacyWorkspaceView.swift`
- Modify: `Sources/MINTCore/Project/ProjectSession.swift`
- Modify: `Sources/MINTCore/ContentView.swift`
- Modify: `Sources/MINT/MINTApp.swift`
- Create: `Tests/MINTCoreTests/LegacyWorkspaceControllerTests.swift`
- Create: `Tests/MINTCoreTests/ProjectShutdownTests.swift`

**Interfaces:**
- Produces: `LegacyWorkspaceController.enter()` and `leave()` transactions.
- Produces: `ProjectSession.suspend()` and `resume()` so a legacy editor never coexists with a mutable active project value.
- Produces: app delegate `projectSession` reference and deferred termination result handling.

- [ ] **Step 1: Write failing mutual-exclusion test**

```swift
func testEnteringLegacyFlushesProjectBeforeConstructingEntryStore() async throws {
    session.updateSelectedDocumentBody("durable before legacy")
    try await controller.enter()
    let durable = try await projectStore.activeProject()
    XCTAssertEqual(durable?.documents[0].body, "durable before legacy")
    XCTAssertEqual(controller.mode, .legacy)
    XCTAssertNil(controller.projectRuntime)
    XCTAssertNotNil(controller.legacyStore)
}
```

The controller receives an `entryStoreFactory` closure so the test can prove construction ordering without adding test-only production methods.

- [ ] **Step 2: Run and confirm RED**

Run: `swift test --filter LegacyWorkspaceControllerTests`

Expected: controller and explicit boundary do not exist.

- [ ] **Step 3: Implement enter/leave lifecycle and compatibility view**

Entering calls `ProjectSession.suspend()`, which runs the transition barrier, flushes, cancels project consumers, and clears its mutable active value without changing the durable active marker. Only then does the controller construct one `EntryStore`. Leaving flushes and releases EntryStore before calling `session.resume()` and reconnecting project consumers. A failed flush leaves the current mode unchanged. The legacy view may reuse `SidebarView` and legacy editor wiring, but it cannot receive `ProjectSession` mutation closures.

- [ ] **Step 4: Run legacy tests and confirm GREEN**

Run: `swift test --filter 'LegacyWorkspaceControllerTests|EntryStoreRecoveryTests|EntryStoreSaveStateTests|LegacyProjectMigrationTests'`

Expected: all selected tests pass.

- [ ] **Step 5: Write failing termination tests**

Test a small `ProjectTerminationCoordinator` with a real temporary `ProjectStore`: success persists the latest body and returns `.terminateNow`; injected store failure returns `.terminateCancel` while the session remains dirty.

- [ ] **Step 6: Run and confirm RED**

Run: `swift test --filter ProjectShutdownTests`

Expected: project termination coordination is absent and AppDelegate flushes only `EntryStore.current`.

- [ ] **Step 7: Implement deferred AppKit termination**

`applicationShouldTerminate(_:)` returns `.terminateLater`, starts one main-actor task, flushes the project or active legacy store, persists positions, shuts down completion/indexing, drains the engine, then calls `reply(toApplicationShouldTerminate:)`. On save error reply `false` and publish the session error. `applicationDidResignActive` schedules session flush without blocking the main thread.

- [ ] **Step 8: Run shutdown, legacy, and full unit tests**

Run: `swift test --filter 'ProjectShutdownTests|LegacyWorkspaceControllerTests|ProjectSessionTests|EntryStoreSaveStateTests'`

Run: `swift test`

Expected: 0 failures; environment-dependent fixture skips remain explicit.

- [ ] **Step 9: Commit Task 9**

```bash
git add Sources/MINT Sources/MINTCore/Legacy Sources/MINTCore/ContentView.swift Tests/MINTCoreTests
git commit -m "feat(app): isolate legacy access and flush project shutdown"
```

### Task 10: Replace Smoke Coverage with the Real Project Path

**Files:**
- Modify: `scripts/smoke-mint-app.sh`
- Modify: `scripts/ui-smoke-mint-app.sh`
- Modify: `Tests/MINTCoreTests/SmokeConfigurationTests.swift`
- Modify: `README.md` only if its launch instructions still state that model selection is mandatory.

**Interfaces:**
- Consumes: project-owned first-run and editor runtime from Tasks 1–9.
- Produces: deterministic clean-home, relaunch, A/B, menu, and no-model smoke evidence.

- [ ] **Step 1: Change the UI fixture to omit `entries.json` and assert the project body**

Seed or create a project whose initial body is `project-$TOKEN`, type `edited-$TOKEN` through the real editor, terminate normally, and inspect the active project manifest plus its referenced content file. Remove the old success condition that searches `entries.json`.

- [ ] **Step 2: Run the UI smoke and confirm RED before app implementation is accepted**

Run: `scripts/build-mint-app.sh && scripts/ui-smoke-mint-app.sh`

Expected before the cutover: failure because the old app edits EntryStore. Expected after Tasks 1–9: success against the project content file.

- [ ] **Step 3: Add clean Fiction/General, relaunch, switching, menu, and no-model cases**

Each case uses a distinct `CFFIXED_USER_HOME`; never use real manuscripts. Assert no `entries.json` is created in normal project mode and no model download directory appears. Exercise Fiction and General creation, type/save/quit/reopen, document switch, A -> B -> A, new/rename/trash commands, import cancellation, malformed import, and successful legacy import with byte-identical source.

- [ ] **Step 4: Run complete release-proportional verification**

Run in order:

```bash
swift build
swift test
swift build --product MINTBench
scripts/prepare-metallib.sh
scripts/build-mint-app.sh
scripts/smoke-mint-app.sh
scripts/ui-smoke-mint-app.sh
```

Expected: all commands exit 0. Record any CoreData/Contacts sandbox noise separately from test failures; do not describe noisy output as pristine.

- [ ] **Step 5: Perform real-editor manual smoke where automation cannot create marked text**

With an isolated temporary project, verify Korean IME composition produces no Ghost while marked, Tab accepts full Ghost, right-arrow accepts the next unit, Escape rejects, undo remains within the selected document, and image/math content survives A -> B -> A. Do not use a real user library.

- [ ] **Step 6: Commit Task 10**

```bash
git add scripts Tests/MINTCoreTests/SmokeConfigurationTests.swift README.md
git commit -m "test(app): smoke the project-owned writing path"
```

### Task 11: Final Review and Pull Request

**Files:**
- Review: all branch changes relative to `origin/main`
- Update: `docs/superpowers/plans/2026-09-12-project-session-runtime.md` checkboxes only for genuinely completed steps.

**Interfaces:**
- Produces: a reviewable PR referencing #118 without claiming #118 or #119 complete beyond evidence.

- [ ] **Step 1: Run plan self-audit against the approved spec**

Confirm every spec section maps to a completed task and search changed production files for accidental `EntryStore` construction outside the legacy boundary.

Run: `rg -n 'EntryStore\(' Sources/MINT Sources/MINTCore`

Expected: matches only in explicitly named legacy composition or previews/tests, never the normal project runtime.

- [ ] **Step 2: Inspect diff and repository state**

Run:

```bash
git diff --check origin/main...HEAD
git status --short
git log --oneline --decorate origin/main..HEAD
```

Expected: no whitespace errors, no untracked implementation files, and bounded commits for #118 only.

- [ ] **Step 3: Use the verification-before-completion skill and rerun required evidence**

Do not reuse old output. Run the complete Task 10 verification commands and capture exact pass/failure counts.

- [ ] **Step 4: Use the requesting-code-review skill**

Review ownership boundaries, cancellation-after-activation semantics, main-actor reentrancy during flush, path validation, legacy source preservation, duplicate UUID isolation, IME, undo, model gates, and UI smoke truthfulness. Fix every accepted issue through a new failing regression test.

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin codex/118-project-session-runtime
gh pr create --base main --head codex/118-project-session-runtime --title "feat: make ProjectSession the writing runtime" --body-file /tmp/mint-118-pr-body.md
```

The PR body must reference #118, list exact verification evidence, identify #150/#151 coordination boundaries, and state any acceptance item that remains unverified. Do not use `Closes #118` unless the complete current issue acceptance contract and required CI/E2E evidence are satisfied.
