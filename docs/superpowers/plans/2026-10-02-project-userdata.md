# Project UserData Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline; no subagents or approval handoffs, per user instruction.

**Goal:** Persist existing writer decisions separately from rebuildable Intelligence on the authoritative project runtime.
**Architecture:** Opaque immutable project blobs, a scoped session mutation boundary and a typed writer adapter for migration/consumers/UI.
**Tech Stack:** Swift Codable, existing SHA-256 ProjectStore/ProjectFileSystem, MainActor session, existing SwiftUI tools.
**Spec:** docs/superpowers/specs/2026-10-02-project-userdata-design.md

## Global Constraints
- Generic storage/runtime must not depend on Fiction types; legacy source is immutable.
- UserData/records/<key SHA-256>/<content SHA-256>.data is durable; Intelligence is disposable.
- Keys: 1–128 ASCII identifier bytes (letters/digits/dot/underscore/hyphen), no dot/dot-dot components.
- New manifests use schema 2; readers/import accept schemas 1 and 2 without rewriting the source on load.
- Owner results and model/license approval stay pending; implement inline without CI waits.

## Review Focus
- Deleting a writer record must not cause migration to reseed it from an old archive.
- Failed blob/manifest writes preserve the prior usable manifest and decision values.
- Same document UUID in A/B must not alias writer data or accept stale UI mutations.
- Unknown opaque keys and original legacy metadata survive round-trip/retry.
- Stale evidence remains representable; reindex/schema reset cannot remove writer decisions.

## Task 1: Generic immutable storage
Files: WritingProject.swift, ProjectManifest.swift, ProjectStore.swift, new ProjectUserDataTests.swift.
Interfaces: WritingProject.userData: [String: Data] (default empty); ProjectManifest.userData: [String: ProjectFileRecord] (backward default empty); ProjectStore.userDataPath(key:hash:) throws -> String.
- [x] Write failing storage fixtures: JSON writer values round-trip into UserData records, edit/delete plus previousProject recovery, A/B isolation, blob/manifest failure, corrupt/path/symlink refusal, unknown-key retention and old-field compatibility.
- [x] Run focused RED; implement opaque coding and checked content-addressed save/materialization.
- [x] Run focused/full tests, Swift/bench builds; author review, commit/push stacked Draft PR on #206.

## Task 2: Scoped writer state and migration
Files: ProjectSession.swift, ProjectDocumentSnapshot.swift, writer UserData adapter/migration, LegacyEntryAdapter.swift, MINTApp.swift, writer tests.
Interfaces: updateUserData(_ data: Data?, for key: String, identity: ProjectRuntimeIdentity) throws; WriterDocumentData codec/key(documentID:); injected pre-adoption preparation closure returning verified WritingProject.
- [ ] Add failing session generation/flush/relaunch/stale-A/B and typed legacy migration fixtures.
- [ ] Implement scoped in-memory mutations and writer codec; migrate archived known fields only for absent records with a durable migration marker so deletes stay deleted.
- [ ] Test migration failures/cancellation before activation, and stale-anchor/explicit action round-trip without a model.
- [ ] Run required checks, review and deliver bounded stacked slices.

## Task 3: Prepared consumers and existing tools
Files: project snapshot, CompletionController/BackgroundIndexer adapters, ContentView, WorkspaceShellView, minimal project writer tool and tests.
Interfaces: WriterDocumentData loaded from snapshot opaque bytes; writer mutations use captured runtime identity and existing session flush.
- [ ] Add failing prepared-context/character editing/context control/durable action isolation tests.
- [ ] Connect genre/cards/overrides/rejected names/recorded conversations to project readers, without disk reads or LLM calls in hot paths.
- [ ] Expose minimal editing/access in existing tool locations; keep legacy persistence unchanged and style separate.
- [ ] Run full/build/bench and applicable native app smokes; review, push/attach Draft PRs and record remaining owner/#151 evidence.
