# Project-owned writer data (#111)

## Intent and authority

The writer's cards, overrides, rejected names, context pins/exclusions and explicit decisions must survive project switching, relaunch, Intelligence replacement and recovery without a model. The current #111 body is the contract; its historical broad canon/retrieval plan is not new scope. The user explicitly requested further implementation while deferring tests/results, after the M1 owner gate was reported. Continue independent M2 implementation; leave model/license choices and release approval with the owner.

This is architectural work. The user requested uninterrupted inline implementation with no subagents or repeated approval handoffs; spec/plan author review supplies implementation checkpoints under that instruction.

## Storage boundary

Use opaque keyed bytes in WritingProject.userData. Generic project/session/storage code must not import CharacterCard, NarrativeOverride or any Fiction type. ProjectManifest references content-addressed immutable blobs under UserData/records/<key SHA-256>/<content SHA-256>.data. Keys are nonempty single ASCII identifiers (letters, digits, dot, underscore, hyphen), at most 128 bytes, excluding dot/dot-dot path components. Missing old manifest/value fields decode to an empty dictionary.

UserData blobs are verified with the existing ProjectStore path/hash/lock rules before manifest publication and activation. The manifest commits manuscripts and user data together. Editing/deleting a record retains previous immutable bytes for previous-project recovery; Intelligence writes/removal never mutate these references. Unknown opaque keys are retained by normal loaded-project edits. No in-place entries.json migration or cache-based writer persistence.

New writes use manifest schema 2 so older schema-1 apps refuse the project rather than silently discard UserData references on save. Current readers/import accept schemas 1 and 2; loading/importing an old project alone does not rewrite its source. Its next successful save publishes schema 2 with a preserved previous manifest.

## Runtime and writer adapter

ProjectSession remains the sole mutable active owner. A captured full ProjectRuntimeIdentity gates opaque mutations, advances the session generation, notifies prepared readers and uses the existing dirty/autosave/flush contract. In-flight flush and transition failure must preserve the latest edits and previous valid owner.

WriterDocumentData is a separate typed adapter keyed by persistent document ID within the project. It preserves genre, cards including lock/auto-registration state, rejected names, NarrativeOverride values/anchors/dates and recorded conversations. Context pins/exclusions are existing override kinds. Intentional/dismiss actions remain distinct durable records with EvidenceAnchor, without a new broad canon UI or style-profile merging.

Legacy migration reads only a verified archived source, extracts known fields without rewriting the source, and preserves the original archive (including unknown fields). Already-migrated projects need the same missing-record migration before adoption; existing edited/deleted records take precedence and must never be reseeded from the archive. Corrupt/unsupported writer data is an error, not a silently empty value. A generic preparation boundary may be injected into ProjectSession for the app's typed migration, with all failure/cancellation before target activation/adoption.

## Consumers and minimal UI

Prepared project snapshots carry opaque data. Completion/indexing adapters decode already-loaded writer values; no disk/network/rebuild enters prediction or typing hot paths. The existing project tool location exposes basic character/genre editing and existing context controls with captured ownership. Keep legacy compatibility on its existing storage path. Do not construct an EntryStore for a project or add competing project persistence there.

Stale anchors retain writer values. Existing NarrativeOverrides re-anchoring can report stale scene decisions without deleting them; EvidenceAnchor remains the cross-layer evidence type for durable actions. Style preferences stay in WriterStyleProfile.

## Verification and delivery

Use deterministic temporary project fixtures. Regressions cover raw opaque round-trip, physical UserData placement, cache reset, previous-manifest recovery, A/B same-document-ID isolation, interrupted blob/manifest commit, malicious paths/symlinks, corrupt blobs, stale runtime rejection, migration retry precedence and writer add/edit/delete/relaunch without inference. #151 consumes this manifest boundary for later backup/restore; do not invent a second recovery system here. Full tests/build/bench and applicable app smoke precede each bounded stacked Draft PR. No remote CI waiting, merging, issue closure or owner checkbox completion.
