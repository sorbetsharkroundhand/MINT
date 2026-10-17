# Original-backed legacy consistency checks

## Intent and authority
The owner directs completing remaining UI/internal features with recommended choices, written designs/plans, inline reviews and no subagents/repeated approval. This architectural sub-project starts #109; it does not close the remaining knowledge/object/time/identity rules. Actual MINT/native/model acceptance remains owner-later. Existing #107/#108 foundations are merged and current #109 has no active implementation PR.

## Problem and decision
The current background reader publishes legacy ConsistencyWarning values without evidence and folds discourse order across flashbacks. Its death substring check also accepts negated/uncertain death labels. Preserve existing dead-speaker and three-utterance honorific detection, but introduce an original-aware production overload and route both background publications through it.

Alternatives considered: merely attaching a quote after the old detector loses later valid warnings when an early flashback consumes deduplication; treating every legacy model delta as a fact invents authority. Use an independent evidence-aware pass on the captured original and snapshot. Keep the old detector API for legacy callers/tests, explicitly unverified and never published by the background reader.

## Contract
- `ConsistencyWarning.evidence` contains original EvidenceAnchor values. The new `check(snapshot:characters:source:)` returns only warnings with all required literal original proof. The legacy two-argument API remains source-compatible and is not a visibility grant.
- The supplied original must have exactly the snapshot outline. Validate literal UTF-16 quotes and offsets. Ambiguous event quotations refuse. Unregistered or duplicated character identities refuse. Cancellation returns no partial result.
- Suppress non-present scene types and any utterance/event overlapping non-present or uncertain narrative segments. Do not consume deduplication for suppressed material. Unknown absolute story time never invents a time/location conflict.
- A dead-speaker warning needs the latest eligible prior completed-scene vitality assertion and the original speech. Competing values in that latest scene or missing/ambiguous evidence remain quiet, including when an unverified newer state would otherwise revive an old death warning. Non-present events do not affect current state.
- Death values use a closed affirmative vocabulary (`사망`, `사고로 사망`, `죽음`, `죽었다`, `죽었음`); arbitrary death substrings, negation, uncertainty and conjecture refuse. The original must itself be one complete closed affirmative death clause for this uniquely registered name, not another character or an unrelated quoted passage. No natural-language certainty is inferred from absence.
- Honorific changes require three verified preceding utterances of the same directed pair/politeness and a verified opposite utterance. Retain all four anchors; invalid/shifted/unknown samples reset the pair establishment. Duplicate speech offsets cannot establish a streak. One warning per pair and one dead warning per character, deterministic source ordering.
- Both production BackgroundIndexer hydration/pass callbacks supply their captured body. Existing scope/generation/body/priority/cancellation gates remain. Every edit retires published warnings synchronously, including memory-pressure pauses; rebuilding original proof stays in background. Prepare per-character vitality indexes once and query them by binary search; do not rescan all events per utterance. No new disk scan, inference, schema migration or prediction-path work.
- Narrative warning source navigation validates its original again against the current document and refuses stale data; no fuzzy jump. It does not mutate manuscripts or writer decisions.

## Verification and limits
New source-backed XCTest fixtures use real DialogueAttribution and current outline/sidecar construction. Cover death/honorific positives, negation, flashback/uncertain ranges, missing/duplicate/Unicode evidence, newer unverified/competing state, deduplication and stale/cancelled source. Preserve existing legacy tests. Build/full Swift tests/MINTBench and exact-head/predecessor-main/merged-main all-three CI remain required. Synthetic tests are not actual product/IME/VoiceOver acceptance. Remaining #109 rules and #110 bounded judging are separate bounded successors.

Inline author review: evidence gates precede deduplication; missing new metadata never upgrades confidence. No requirement assumes named scene hashes are durable IDs or that discourse order equals absolute story time. No owner signoff or semantic claim is fabricated.
