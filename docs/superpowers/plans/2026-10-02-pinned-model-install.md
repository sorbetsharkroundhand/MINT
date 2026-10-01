# Pinned Model Installation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. Do not use subagents; the user authorized uninterrupted implementation.

**Goal:** Only exact, complete, integrity-verified local model installations can be loaded.
**Architecture:** A compiled manifest and shared actor own staging, verification and atomic publication. The UI and MLX loader consume the same installation, replacing the shard-presence heuristic and mutable remote load.
**Tech Stack:** Swift actors, CryptoKit streaming hashes, Foundation filesystem, pinned HuggingFace/MLX APIs.
**Spec:** docs/superpowers/specs/2026-10-02-pinned-model-install-design.md

## Global Constraints
- Keep writing/model-free use and user manuscripts available.
- No new dependency, shared Hub-cache deletion, mutable revision or owner lineup approval.
- Reject traversal/symlinks; run work outside the main actor with cancellation/yielding.
- Failing regression coverage precedes implementation; verify each PR locally.

## Review Focus
- Partial/corrupt or receipt-only installs must never become ready.
- Changed revision/inventory must not reuse readiness from another identity.
- Cancellation and duplicate requests must not publish stale completion.
- Symlink/path escape must preserve all outside files.
- Engine loading must consume verified local data and never silently use main.

## Task 1: Immutable manifest metadata
Files: ModelInstallManifest.swift, PinnedModelCatalog.swift, PinnedModelManifestTests.swift.
Interfaces: ModelInstallManifest(id:revision:files:), validate(); File(path:size:digest:algorithm:); PinnedModelCatalog.manifest(for:).
- [x] Write and run failing tests for mutable revision, missing integrity, unsafe/duplicate/incomplete paths and absent preset metadata; implement pinned Hub inventories and rerun to green.
- [x] Run the isolated suite, Swift/bench builds, review inline and open a Draft PR on #197.

## Task 2: Owned installation state
Files: ModelInstallationStore.swift, ModelInstallationTests.swift.
Interfaces: Task 1's manifest; ModelInstallationStore(root:), state(for:), install(_:download:onState:), cancel(_:), directory(for:). Download receives the manifest, file and safe destination asynchronously.
- [x] Write and run failing disposable-file tests for receipts, full digest verification, cancellation/retry, revision isolation, duplicate requests, unsafe paths, unlisted weights and unpinned indexed shards.
- [x] Implement, rerun focused/full isolated tests and Swift/bench builds; expect zero failures and successful builds. Review inline and open a stacked Draft PR.

## Task 3: Real download and inference integration
Files: ModelDownloadManager.swift, CompletionEngine.swift, ModelChip.swift and focused lifecycle tests.
Interfaces: Task 2's actor; pinned HubClient.downloadFile(at:from:to:revision:); MLX local loadModelContainer(from:using:).
- [x] Write failing manager tests for partial/corrupt interruption, retry and late cancellation results using only a fixture-file downloader.
- [x] Replace heuristic readiness and mutable remote loads; show verification state and actionable metadata failures.
- [x] Run focused/full isolated tests, Swift/bench builds and a native archive build. Review inline, commit and open a stacked Draft PR. Record unavailable real-model evidence honestly; do not wait for CI.
