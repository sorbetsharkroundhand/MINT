# Model Removal Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. No subagents or intermediate approval pauses, per explicit user instruction.

**Goal:** Safely remove or replace owned pinned model resources with coherent installation/selection/cache state.
**Architecture:** Serialized actor deletion using validated ownership and recoverable tombstones; controller drains inference before committing lifecycle changes.
**Tech Stack:** Swift actors/tasks, existing ProjectPaths and receipts, SwiftUI Settings.
**Spec:** docs/superpowers/specs/2026-10-02-model-removal-design.md

## Global Constraints
- Delete only proven model-owned resources; preserve manuscript/Intelligence/shared cache/settings data.
- Interrupted tombstones never become ready; failed target install leaves the prior model intact.
- No mutable revisions, real models/manuscripts, new dependencies or owner-check edits.

## Review Focus
- Concurrent transfer must retire before filesystem removal; no late publication.
- Unknown files/symlink escapes must prevent any deletion.
- Same-ID replacement must keep only the intended new revision and clear old memo state.
- Cancelled/interrupted deletion must recover without reactivating deleted resources.
- Runtime load callbacks must not republish old state after removal/replacement.

## Task 1: Owned filesystem lifecycle
Files: ModelInstallationStore.swift, ModelDownloadManager.swift state mapping, ModelRemovalTests.swift.
Interfaces: remove(_ id: String) async throws; replace(_ id: String, with: ModelInstallManifest, download: Download) async throws -> URL; ownedModelIDs() -> [String]. Store retains per-model deletion Tasks and rejects install while deleting/tombstoned.
- [x] Write failing tests for removal, in-flight transfer drainage, preserved outside/unmanaged/symlink data, interrupted tombstone recovery, failed target replacement and same-ID revision replacement.
- [x] Implement preflight ownership/inventory, tombstone move/recovery, serialization and memo cleanup.
- [x] Run focused/full isolated tests and Swift/bench builds; author-review inline, commit and stacked Draft PR.

## Task 2: Runtime and Settings
Files: CompletionEngine.swift, CompletionController.swift, SettingsView.swift, ModelLifecycleIntegrationTests.swift.
Interfaces: unload() async throws; controller removeModel(_:store:) async throws and replaceModel(with:) async throws, joined load cancellation and generation-bound callbacks; Settings model inventory/removal feedback.
- [x] Add failing tests for active selection/report/authorization cleanup, preserved unrelated preferences, failed removal coherence and stale publication guards.
- [x] Drain/unload engine, guard concurrent lifecycle requests, commit selection only after verified operation, expose Settings controls.
- [x] Run focused/full isolated suite, Swift/bench builds and native archive/sandbox smoke; review inline, commit and stacked Draft PR. No CI wait.
