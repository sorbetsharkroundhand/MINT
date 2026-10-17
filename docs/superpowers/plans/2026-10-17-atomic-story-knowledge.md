# Atomic Story Knowledge implementation plan

> Execute inline with superpowers:executing-plans and regression-first tests. No subagents; owner-delegated UI/internal choices use written artifacts and inline review. No repeated approval prompt.

**Spec:** `docs/superpowers/specs/2026-10-17-atomic-story-knowledge-design.md`

**Goal:** Evidence-backed temporal facts and prepared conservative queries, integrated with the actual existing scene producer.

**Global constraints:** Original UTF-16/evidence and explicit project/document/entity identity; discourse != story time; unknown confidence/time stays unknown; no summary truth. Preserve existing public behavior, durable WriterDecision/NarrativeOverride data, IME/Ghost/focus/Undo/save/format invariants and no-model editing. No new dependency, model operation, local product/UI-smoke launch or cache deletion. Isolated temporary CFFIXED_USER_HOME and locked resolution. Sequential bounded delivery; ready successor PR validation may overlap predecessor main CI after predecessor merge, but successor merge waits for both predecessor main and its own exact-head all-three CI; standing merge authorization applies. Final native acceptance remains #119.

## Review focus
1. Unknown/uncomparable/invalid time or confidence must never become a hard resolved fact; future acquisition and later-discovered flashbacks stay behind discourse cutoff.
2. Explicit destroyed→restored transitions fold in story order, and expired/ambiguous state never resurrects an older value.
3. Aliases, repeated scenes/quotes and canonically equal different originals cannot grant the wrong source/entity authority.
4. Prepared snapshot creation runs only at the existing background seam; no new hot-path scan, inference, disk access, full rebuild or writer-data mutation.

### Task 1: Atomic domain values and temporal validity

**Files:** Create `Knowledge/StoryKnowledge.swift`, `Tests/MINTCoreTests/StoryKnowledgeTests.swift`.

**Interfaces:** Public Codable/Equatable/Sendable `StoryInstant`, `StoryInterval`, `StoryFactOrigin`, typed character/knowledge/relationship/object/world-rule payloads and `StoryFact`. Interval overlap is a tri-state result (overlap/disjoint/unknown); different timeline IDs are never ordered. Fact construction requires explicit StoryMemoryScope, and equality preserves project/legacy identity even for the same document UUID and original. Validation checks original range/evidence document relation, required values/IDs and optional finite [0,1] confidence. Derived fact IDs are not persistent manuscript IDs. No changes to existing extractors/storage yet.

- [x] Write failing tests for known/unknown/cross-timeline overlap, malformed bounds/ranges/confidence, all typed value round-trips and original Unicode/evidence identity.
- [x] Run the new suite; retain genuine RED before implementation (use minimal compiling declarations if needed).
- [x] Implement immutable values/validation only; run focused new/EventLog/StateDelta/Narrative/hierarchy tests, build/full tests/MINTBench.
- [ ] Review inline, commit `feat: define atomic temporal story facts`, publish/attach after quality-access predecessor merge; merge waits for predecessor main CI, merge on exact-head all-three checks, synchronize clean primary main and verify merged-main CI. This is partial #107.

### Task 2: Prepared temporal queries and exact entity resolution

**Files:** Create `Knowledge/StoryKnowledgeSnapshot.swift`, `Knowledge/StoryEntityResolver.swift`, `Tests/MINTCoreTests/StoryKnowledgeQueryTests.swift`, `Tests/MINTCoreTests/StoryEntityResolverTests.swift`.

**Interfaces:** `StoryKnowledgeSnapshot(scope:source:facts:entities:decisions:)` verifies full scope, registered subjects and exact raw UTF-16 evidence once; retains only source revision/length, verified facts and slot/character indexes. `observations(before:)` and `observations(of:before:)` expose prepared observations. Typed `characterState(of:field:at:before:)`, `characterKnowledge(of:fact:at:before:)`, `relationship(from:to:at:before:)`, `objectState(of:field:at:before:)`, `worldRule(id:at:before:)` and `knows(_:fact:at:before:)` return `StoryFactResolution.resolved(StoryFact)` or `.unknown`. Confidence gate0.8; actual matching confirmed WriterDecision authority may substitute for a score. Unknown/uncomparable time, conflicting active ranges, expired latest observation and explicit unknown stance refuse. `StoryEntityResolver(characters:objects:rules:)` consumes registered CharacterCards plus `StoryNamedEntity` registrations; exact names/aliases resolve only unique IDs in their explicit domain, no prefix or auto-registration. Missing source hints or conflicting duplicate derived IDs refuse; invalid cutoffs do not clamp to future source. No original text retained for queries.

- [x] Write/run failing flashback/cursor/acquisition/unknown/conflict/expiry/destroy→restore/directed-relation/alias-collision tests.
- [x] Implement prepared indexes and queries with no source/model/storage work. Preserve all existing EventLog/StateDelta semantics.
- [x] Run focused suites, build/full tests/MINTBench; review all time/identity edge cases inline.
- [ ] Commit/publish bounded query PR after Task1 merge (merge gated on Task1 main CI), attach, inspect feedback and merge on all-three exact-head checks; synchronize/verify merged main. Partial #107 until adapter delivery.

### Task 3: Verified existing producer adapter and snapshot integration

**Files:** Create `Knowledge/StoryKnowledgeProjection.swift`, `Tests/MINTCoreTests/StoryKnowledgeProjectionTests.swift`; extend `Knowledge/KnowledgeStore.swift`, `Knowledge/BackgroundIndexer.swift` at the existing makeSnapshot seam and relevant scoped snapshot tests only.

**Interfaces:** Projection consumes immutable body/outline/actual sidecar events+insights/current registered characters and explicit StoryMemoryScope. Exact original unique scene-local quotes become EvidenceAnchors; legacy records retain whole-scene discourse visibility and unknown story time/confidence. KnowledgeSnapshot gains a compatible optional/default prepared StoryKnowledgeSnapshot property. Writer-owned records are neither copied into the derived cache nor mutated.

- [ ] Write/run failing actual-sidecar projection/publication tests for tombstones, missing/ambiguous/repeated/Unicode quotes, registered-ID filtering, coarse future cutoff and project isolation.
- [ ] Implement projection at existing background preparation/publication, no new inference pass or persistence/schema change.
- [ ] Run all Story/EventLog/StateDelta/hierarchy/project-context regressions, build/full tests/MINTBench and separate whole-feature inline review; important findings require RED→GREEN fixes.
- [ ] Commit/publish/attach bounded integration PR after Task2 merge (merge gated on Task2 main CI), merge only on exact all-three checks and verify merged main. Record #107's completed core evidence, remaining producer/UI scope and final acceptance truthfully; preserve #110/#113/#115/#270/#119 contracts.

Inline plan review: Task1 values feed Task2 snapshot indexes; Task3 uses those exact types and the existing StoryMemoryScope/source evidence seam. Legacy arrays/public queries remain compatible. No type/access/scope conflict or need for a new durable schema was found. Retain local evidence/ledgers and owner artifacts.
