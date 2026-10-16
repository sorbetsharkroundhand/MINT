# Explicit writing reports and shared admission

Task 10 adds app-owned offline diagnostics lifetime and an explicit document-report API. Native proofread editing and result presentation remain Tasks 11–12. This does not claim actual-app, IME, accessibility, Store, or general Korean grammar acceptance.

`WritingDiagnosticsRuntime` owns one lazy Korean native worker shared by local analysis and private full-report sessions. It observes Low Power and thermal policy, receives the existing single memory-pressure monitor, and drains native release during termination. Project transitions discard derived ownership. No model or network setup is required to write, and no shipping LLM is selected.

## Reports

`scanDocument` captures an immutable document/profile and verifies current project/generation ownership. Explicit preparation runs off the main actor and is cancellable at line, bounded-piece and atomic index-admission boundaries. An immutable projection retains cached eligible prose totals and maps original source, including formatted prose and exclusions. The Task 8 provider owns its report session, independent of the local engine generation, over the same serial worker. Local work takes priority between admitted chunks.

Each report has a single consumer and a channel with at most one buffered event. Progress counts visited eligible prose UTF-16 units, excluding overlap. Final coverage separately describes assessment and unsupported/dirty regions; progress reaching total does not imply complete assessment. Findings and progress are streamed; the channel must have capacity before another chunk is admitted. Cancellation, dropping the iterator, project/profile changes, foreground Ghost, composition, or policy pauses stop future admission and wake blocked senders. One already admitted native C call may drain. Report events never replace local controller state.

Coverage metadata has a separate 16 MiB budget. If exact coverage exceeds it, preserve conservative whole-source dirty and single unsupported bounds, discard precise assessed claims and remain partial. Finding packets are bounded separately. Evidence anchors retain a bounded original source prefix while full mapped ranges describe the pattern; persisted long intentional occurrences are verified against their exact owned source revision through source pieces, without copying a second whole quote.

## Pressure and lifetime

Warning evicts the local derived input cache and pauses optional work. Critical cancels pending work and releases native resources after the admitted call drains. A newer normal event cannot reopen work before both native and shared MLX release finish. Existing completion and indexer pressure consumers remain intact. Foreground completion delivery composes weak owner-keyed observers with the existing callback; repeated connection is idempotent.

The manuscript and project style decisions are never pressure-shedding targets. Runtime stop removes observers, cancels owned work and clears the reader; termination awaits release. Local actual-app launches are intentionally deferred to owner verification.

## Deterministic verification

Report tests cover real pinned-backend mapped evidence/progress, immutable projection totals, slow consumers, iterator termination, long intentional source ownership, cancellable preparation, fragmented coverage overflow and a blocked old report racing a new project's local result. Pressure tests cover critical/normal drain, shared MLX release ordering, one monitor, and callback composition, alongside the existing memory suites. A backend factory barrier tests orchestration only; language claims use the real pinned backend fixtures.

Task 10 validation on 2026-10-16: build, full 1,118 tests (2 existing skips, zero failures), MINTBench and the frozen backend `--verify` gate passed. The isolated native probe measured cold initialization 1.053 s, peak resident 869,498,880 bytes, warm 1,024-unit analysis 14.46 ms and admitted-call cancellation drain 14.94 ms, all within the unchanged frozen limits. Output is retained under `build/korean-backend-validation/task-10-frozen-verify-20261016`; no MINT process was launched.
