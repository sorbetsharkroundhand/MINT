# Sandbox Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. The owner requires inline work without subagents and explicitly authorized implementation without another approval handoff.

**Goal:** Safely import a development project into container storage and prove the native target's sandbox storage contract.
**Architecture:** Extend ProjectStore preparation, reuse ProjectSession activation, share folder selection across onboarding and commands, and probe the production storage location with real sandbox entitlements.
**Tech Stack:** Swift 6, SwiftPM, Foundation/AppKit, Xcode, macOS 14+, shell.
**Spec:** `docs/superpowers/specs/2026-10-01-sandbox-storage-design.md`

## Global Constraints

- Preserve source bytes, manuscript IDs, assets, trash, opaque UserData and history; no in-place legacy migration.
- Reject destination collisions, traversal, symlinks and stale source snapshots; failed/cancelled imports preserve the active owner.
- No Fiction dependencies in generic storage; no model/metallib fixes or Apple account operations.
- Use CFFIXED_USER_HOME and disposable fixtures; owner checks and CI inspection remain with the owner.
- Keep the existing unsigned archive and existing CI jobs; base the follow-up on PR #194.

## Review Focus

- A source writer changing files during copy must prevent activation: Task 1 fault-injection test.
- A dangling or nested symlink must never copy outside bytes: Task 1 unsafe-tree tests.
- An existing ID, including the selected source itself, must not be overwritten: Task 1 collision test.
- An error or cancellation after preparation must retain the old session and active marker: Task 2 handoff tests.
- A container-shaped path without effective sandboxing must not count as proof: Task 3 denied-external-write probe.

### Task 1: Prepare a verified modern project copy

**Files:** Create `Sources/MINTCore/Project/ProjectFolderImporter.swift`, `Tests/MINTCoreTests/ProjectFolderImportTests.swift`; extend `ProjectManifest.swift` for a localized collision error.
**Interfaces:** Produces `ProjectStore.prepareProjectImport(from: URL) throws -> WritingProjectID` on the existing actor, using the existing ProjectFileSystem and store lock.

- [ ] Write `testPreservesProjectTreeAndReopensWithoutSource`: both writing modes; source/destination byte inventory equal; ID/assets/trash/UserData/previous snapshot preserved; old active marker unchanged until explicit activation; reopen after source removal.
- [ ] Write safety tests for corruption/schema/IDs, collision, nested/dangling links and unsafe references, copy/verification fault, concurrent source change, and task cancellation. Assert the previous marker and source inventory, and no partial new project.
- [ ] Run `swift test --filter ProjectFolderImportTests` under an isolated CFFIXED_USER_HOME. Expected RED: absent import behavior; introduce only a signature stub if needed to observe runtime failure.
- [ ] Implement preparation under the destination lock: reject unsafe source and collisions, exclusively create an owned inactive target, copy each safe regular file/directory with cancellation checks, compare inventories/hashes, validate with ProjectStore, recheck source, and clean only the owned target on error.
- [ ] Run the same tests. Expected GREEN: every named safety case passes. Commit `feat: prepare verified non-destructive project folder imports`.

### Task 2: Connect one folder-selection and activation flow

**Files:** Modify `ImportProjectCoordinator.swift`, `FirstRunView.swift`, `AppCommands.swift`, `FirstRunStateTests.swift`, `ImportProjectCoordinatorTests.swift`; create `Onboarding/ProjectImportPanel.swift`.
**Interfaces:** Consumes Task 1's preparation; produces `ImportProjectCoordinator.importProject(from: URL) async throws -> WritingProjectID` and `importFolder(from: URL, legacyMode: WritingMode) async throws -> WritingProjectID`. Shared `ProjectFolderSelection` carries `directory: URL` and `legacyMode: WritingMode`; `ProjectImportPanel.select()` returns an optional selection.

- [ ] Write modern coordinator success, cancellation-before-activation, activation-write failure, and folder dispatch regressions; modern manifest takes precedence over entries.json, and legacy folder import retains images. Change the existing cancelled-panel test to the shared folder route.
- [ ] Run `swift test --filter 'ImportProjectCoordinatorTests|FirstRunStateTests'`. Expected RED: modern/folder import unavailable or incorrect handoff.
- [ ] Add balanced folder security-scoped access, prepare/checkpoint/session activation, shared directory-only panel, and route onboarding/File-menu imports through it. Modern import retains manifest mode; only legacy asks Fiction/General. Preserve focus requests after success and legacy-workspace disabling.
- [ ] Run the same tests plus ProjectFolderImportTests. Expected GREEN: verified activation, cancellation/failure retention, modern/legacy dispatch, and panel cancellation pass. Commit `feat: import project folders through the verified session flow`.

### Task 3: Enable and verify sandbox container storage

**Files:** Create `Distribution/MINT.entitlements`, `scripts/test-mint-sandbox-storage.sh`; modify native target build settings, `.github/workflows/ci.yml`, `MintStorageLocation.swift` comments, and `Distribution/README.md`.
**Interfaces:** Consumes the existing standard MintStorageLocation source and unsigned archive; produces the sandbox entitlements and an isolated executable runtime probe.

- [ ] Write the probe/configuration check first. Expected RED: target entitlements or sandbox configuration missing; the probe must also fail if the container location escapes or an ungranted external write succeeds.
- [ ] Enable sandbox + user-selected read/write + optional-download network client on both target configurations. Keep unsigned archive signing disabled. Compile the actual storage-location source into a uniquely identified ad-hoc-signed test app; isolate CFFIXED_USER_HOME to its owned container and assert effective entitlements, container write/reopen, and denied outside write.
- [ ] Run `scripts/test-mint-sandbox-storage.sh`. Expected GREEN: genuine sandbox and isolated storage checks pass. Add it to the archive CI job and document project-folder/legacy import boundaries.
- [ ] Run isolated focused tests, full `swift test`, `swift build`, `swift build --product MINTBench`, archive build and archive-validation regressions, plus shell/plist/YAML/diff checks. Expected: success, no changed dependency pins or weakened jobs.
- [ ] Review the complete branch inline against the spec and Review Focus; fix material findings with regressions. Commit `build: enable and verify sandbox container storage`.
- [ ] Push two bounded stacked draft PRs: preparation based on `codex/173-unsigned-archive`, then UI/sandbox based on `codex/174-project-import`. Attach both and record local evidence. Keep #174 open; owner handles CI and representative-install verification.
