# Memory Policy Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. User instruction excludes subagents and intermediate approval pauses.

**Goal:** Refuse unsupported model use before download/MLX allocation and expose only approved models fitting detected unified-memory tiers.
**Architecture:** Pure injectable hardware/catalog policy shared by settings, download and inference; explicit candidate evaluation remains separate from release selection.
**Tech Stack:** Swift value types, Foundation/Metal capability snapshot, existing pinned metadata.
**Spec:** docs/superpowers/specs/2026-10-02-memory-policy-design.md

## Global Constraints
- Tier floors: 8/16/24/32 GiB; budget: 60% of min(physical, recommended working set).
- Empty approved lineup until #180/#155 owner evidence; preserve saved IDs and editor access.
- No model allocation, cache scan, real weights or manuscripts in unit tests; no new dependency.

## Review Focus
- Unapproved and changed-revision models must fail before network/MLX setup.
- No arbitrary default when catalog has conflicting defaults.
- A smaller Metal working set wins over a larger physical-memory tier.
- Saved settings remain durable even when their model becomes unsupported.
- Candidate measurement cannot make a candidate a normal release choice.

## Task 1: Pure memory policy
Files: Sources/MINTCore/Inference/ModelMemoryPolicy.swift; Tests/MINTCoreTests/ModelMemoryPolicyTests.swift.
Interfaces: HardwareMemory(physicalBytes:recommendedWorkingSetBytes:hasUnifiedMemory:), tier/budgetBytes; ModelReleaseEntry(id:revision:peakBytes:tiers:defaultTiers:name:); ModelMemoryPolicy(hardware:entries:), availableEntries, defaultModelID, requireLoad(manifest:), evaluatingCandidates(peakBytes:).
- [x] Write failing tests for exact/floor tiers, unsupported hardware, smaller working-set budget, approved default/changed revision, oversized/missing declarations, conflicting defaults and explicit candidate isolation.
- [x] Implement policy, validated selection and current capability snapshot; keep `approvedEntries` empty.
- [x] Run focused/full isolated tests and Swift/bench builds; review inline, commit and stacked Draft PR.

## Task 2: Runtime and selection integration
Files: CompletionEngine.swift, ModelDownloadManager.swift, Settings.swift, SettingsView.swift, Components/ModelChip.swift; focused integration tests.
Interfaces: Task 1's policy; engine accepts immutable policy defaulting to current; same requireLoad guard before install/resource initialization. ModelChoice.all derives from policy entries; new default ID derives from policy. Existing IDs are preserved.
- [x] Write failing tests for unsupported engine preflight, blocked download without creating files, data-driven default, durable saved settings and changed model authorization.
- [x] Guard engine/download/manual selection; expose available choices and a concise pending/unavailable explanation.
- [x] Run focused/full isolated tests and Swift/bench builds; review inline, commit and stacked Draft PR. No CI wait.
