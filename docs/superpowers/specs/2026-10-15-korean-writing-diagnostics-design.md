# Korean Writing Diagnostics Design

Date: 2026-10-15 (Asia/Seoul)
Status: conversational architecture approved; written specification awaiting owner review.
Authority: [#99](https://github.com/sorbetsharkroundhand/MINT/issues/99), [#126](https://github.com/sorbetsharkroundhand/MINT/issues/126), [#158](https://github.com/sorbetsharkroundhand/MINT/issues/158).
Code baseline: `8a5804e78f0463834e8fbd14498d6fa6cca7df43`.

## Intent and approved experience

Give Korean writers useful local proofreading while preserving an uninterrupted writing loop in Fiction and General. A newly edited paragraph is analyzed automatically after typing pauses. Reliable spelling/spacing errors receive restrained inline marks; repeated endings, particles, connectors and rhythm patterns appear as suggestions beside the manuscript. Text changes only after an explicit user action. Ignored findings and learned words survive relaunch and recovery.

The owner approved this architecture on 2026-10-15. The complete expanded release remains required; this document specifies its first independently deliverable sub-project. Full-document results feed the later Review workspace. Actual-app checks are batched after implementation and associated with one candidate artifact. Shipping LLM selection remains owner-manual; proofreading itself requires neither an LLM nor a network connection.

## Existing foundation and boundaries

- `WritingQuality/WritingDiagnostics.swift` already contains diagnostic categories, UTF-16 ranges, `WritingStyleProfile`, a provider protocol and a cancellable engine. Reuse these contracts. Existing tests use fixture providers; they are not Korean-language correctness evidence.
- `ProjectSession` owns document mutations, generations and durable `UserData`. Its current change callback already serves completion and indexing; diagnostics must join that composition without replacing either consumer.
- `LivingMarginModel` already orders and dismisses presentation values. It performs no analysis. Its existing view receives no functional diagnostic action handler yet.
- Native editor text differs from stored Markdown: headings, inline formatting, code fences, alignment wrappers, images and math alter coordinates. A raw offset cannot safely be shared between these representations.
- The AGENTS.md `WriterStyleProfile` responsibility is fulfilled by the existing `WritingStyleProfile` value plus its durable envelope. Do not create a second preference owner or store these preferences in User Canon.

This work adds real providers, incremental orchestration, profile persistence and the first diagnostic presentation/action connection. It does not rebuild completed navigation, search, typography, frame/rail, model installation or storage ownership. Broad Story Intelligence remains in its own #158 children; contextual vocabulary generation and sentence rewriting remain explicit actions under #270/#269.

## Architecture and ownership

```text
Committed editor change / authoritative document snapshot
  -> revision-bearing prose projection and dirty-window index
  -> diagnostics controller: debounce, admission, ownership, memoization
  -> provider engine -> Korean morphology + independent rules
  -> validated source findings
  -> native correctness decorations / Living Margin / Review consumer

User action -> current-source validation -> existing editor mutation + Undo
Style action -> project-owned writing-style profile -> existing autosave
```

Responsibilities are deliberately separate:

| Unit | Responsibility |
| --- | --- |
| `WritingDiagnostics.swift` | Existing language-neutral values and provider composition. Provider ranges address exactly the request text. |
| Prose projection / range map | Extract analyzable prose and map analysis, canonical Markdown and native editor UTF-16 spans. Incrementally splice changed blocks. |
| Diagnostics controller | Own runtime/revision/profile stamps, dirty windows, cache, cancellation, publication and producer health. |
| Korean morphology adapter | Convert one pinned native backend into MINT-owned tokens, sentence/quote boundaries, grammatical families and correction candidates. |
| Korean rule units | Pure token/span-to-finding rules with stable IDs and deterministic thresholds. |
| Style profile repository | Validate/version the durable profile and occurrence suppressions through `ProjectSession.updateUserData`. |
| Presentation/action bridge | Produce margin values, editor decorations and validated explicit replacements. No NLP in a view or `BlockTextView`. |

Keep Foundation-level analysis independent of AppKit and Fiction. Platform resource loading and native decoration/mutation belong at adapters. A diagnostics failure cannot close the document, block saving, alter the manuscript or start model setup.

## Native Korean backend and integration gate

Use a narrow C-ABI adapter for Kiwi, with MINT-owned token types. The candidate is `v0.24.0`, resolved to source commit `6e16bbcfc0940fabccbdde574abb4ea3a659588e`. An upstream Swift wrapper exists, but its package manifest is nested and its C target contains headers/module mapping without the library implementation; the release root has no `Package.swift`. Do not add the advertised repository URL and assume a complete SwiftPM integration.

Prefer the pinned published XCFramework behind a small local package/target that owns the C module and resource lookup. Before production wiring, a self-contained integration validation must establish:

- Swift 6 and macOS 14+ Apple Silicon compilation, linking and executable/archive loading;
- correct native architecture, exported ABI and resource lookup inside both developer bundles and sandboxed archives;
- verified SHA-256 identity for every library/model artifact before adding dependency/resource manifests;
- actual cold initialization, warm analysis, cancellation interval, peak memory and packaged size measurements on synthetic fixtures;
- token positions for Hangul, decomposed text, emoji, newlines and mixed scripts, converted to the exact input's UTF-16 coordinates;
- reproducible packaged notices for the selected artifact and its linked components.

The upstream [LICENSE](https://github.com/bab2min/Kiwi/blob/6e16bbcfc0940fabccbdde574abb4ea3a659588e/LICENSE) declares Apache-2.0. Its [NOTICE](https://github.com/bab2min/Kiwi/blob/6e16bbcfc0940fabccbdde574abb4ea3a659588e/NOTICE) also declares the distributed models under Apache-2.0 and lists distinct third-party obligations, including Eigen MPL-2.0. The historical September LGPL audit is superseded for this exact candidate; bundled-artifact inventory and attribution remain required under #185.

Publisher metadata lists a 37,721,249-byte XCFramework archive and an 87,967,233-byte base-model archive. These compressed download sizes are not measured app footprint or runtime memory. No artifact has been installed or tested by writing this specification. If the published binary fails the gate, repair the adapter using a reproducible build from the same pinned source and validate again; do not silently substitute an unverified dependency or claim native system checking completes the Korean provider.

The small Korean NLP resource is distinct from the owner-selected Ghost LLM. Bundle verified proofreading resources so first use works offline without an AI setup screen. Initialize lazily off-main after idle/admission; startup and writing never wait for initialization. A missing or invalid resource exposes an actionable unavailable state while editing continues normally.

## Input, coordinates and publication

Create immutable analysis windows from canonical document content with a reversible prose segment map. Reuse/extract the existing Markdown/native decoding semantics rather than inventing a second incompatible interpretation. Exclude code, math, image syntax, link destinations and markup punctuation; visible link labels and ordinary prose remain eligible. Inline emphasis and block prefixes must not shift a finding onto unrelated text.

Each window carries project/document identity, runtime generation, native editor revision where applicable, window content digest, profile revision, provider/rule revision and its source mapping. Automatic `.local` provider requests receive the window's prose text; an explicit `.document` request may hold the document's immutable prose snapshot and subdivides it internally. Both primary and related ranges are translated and bounds-checked before publication; provider offsets are never blindly treated as canonical-source or native-editor offsets.

Published findings retain original-source spans and an `EvidenceAnchor`, enclosed in project ownership because `EvidenceAnchor` itself has no project field. `SourceAnchor` supports navigation re-anchoring. A diagnostic ID combines rule identity with its anchored occurrence; scene content hashes are not persistent manuscript IDs.

Native decorations and replacement actions additionally require the current native/source map to match. Ambiguous duplicate passages cannot be resolved by choosing the first matching quote. If an exact mapping cannot be proved, omit the mark and refuse replacement; a source-inspection action may report the finding as stale. Never guess an offset across formatting or media.

## Incremental scheduling

- Enable Korean analysis for Korean prose in both writing modes. Mixed-language tokens retain their positions; unsupported-language spans do not receive invented Korean diagnostics.
- Debounce committed edits for 350 ms. During marked text, cancel queued analysis and withhold overlapping decorations; do not commit composition or change text merely to run proofreading.
- Analyze dirty sentence/paragraph windows. An automatic local request and each native analysis call contain at most 4,096 UTF-16 units including context. Split long paragraphs at safe sentence/grapheme boundaries with at most 256 units of overlap, deduplicating boundary findings. Never split a surrogate pair or composed character.
- Maintain a paragraph/block index and range-map splices. Ordinary edits invalidate intersecting findings, related occurrences and bounded adjacent sentence context. Shift unaffected indexed positions without rescanning every later paragraph.
- Include profile/provider revisions in cache keys; memoize unchanged windows. No whole-document string hashing, Markdown reparsing or native analysis in the keystroke/selection/Ghost path. An edit spanning many blocks schedules only those changed blocks as cancellable chunks.
- Load, recovery and explicit global style changes may rebuild. Explicit full-document/project requests iterate the same bounded native windows in background; they are not a per-keystroke operation. A private per-report Korean rule session carries bounded family/count/quote state across chunks so clause and rhythm results do not depend on chunk placement. It resets on cancellation or document/profile revision change; no such state leaks between projects. Automatic local output describes only its assessed coverage, rather than claiming a whole-document report.
- Admission checks foreground typing/Ghost, memory pressure, thermal state and Low Power Mode. Foreground work cancels queued work immediately; an executing native call must finish within the measured bounded-call limit before another chunk can begin. Do not claim a synchronous C call is interruptible without evidence.
- On memory warning, release reconstructible analysis caches and pause optional scans. On critical pressure, retire the native worker/resources when its current bounded call finishes. Durable profile/manuscript data is retained. Resume only under current runtime ownership and policy.

A newer edit, project/document transition, profile change or cancellation invalidates publication authority. The controller revalidates ownership after each await even if a backend ignores cancellation. Keep unaffected valid findings separate from dirty/pending coverage; pending, unavailable or cancelled text must not be presented as checked and clean. A late full-document report cannot overwrite newer local results.

## Korean correctness and style rules

Morphology identifies grammatical function; suffix-string matching alone does not satisfy this feature. Native token scores and typo costs are not calibrated correctness probabilities.

**Correctness:** expose typo/spacing alternatives from the real Korean provider. Inline severity requires an independently tested unambiguous rule/context, an exact replaceable source span, and no learned-word/intentional suppression. Examples of required positive fixtures include `됬다` -> `됐다` and a morphology-confirmed `할수 있다` -> `할 수 있다`. Plausible proper nouns, dialect, literary spelling and ambiguous lexical substitutions remain suggestions or stay quiet. The upstream typo example `장례희망` is not automatically a high-confidence error in fiction. No general-grammar-completeness claim is made.

**Style:** implement independent rule IDs and explanations for repeated lexical words, particles, connective/final ending families, connectors, redundant causality, long connective chains, repeated sentence starts, sentence-length outliers and paragraph rhythm. Every explanation references the original occurrences. Suggestions are not correctness errors.

Initial deterministic behavior:

| Pattern | Standard behavior |
| --- | --- |
| Repeated endings/particles/connectors/lexical words | Same relevant morphological family in 3 adjacent clauses/sentences within one paragraph. Window bounds above still apply. |
| `-는데` and causal `-아서/-어서/-여서` | Normalize inflections by grammatical family, preserving actual evidence ranges. |
| Redundant causality | An explicit causal ending followed by a causal connector such as `그래서` at the same clause transition; report as a style suggestion. |
| Connective chain | 4 or more connected clauses in one sentence; report the chain, not one warning per token. |
| Repeated sentence start | Same first two lexical forms in 3 adjacent sentences, excluding formatting/punctuation. |
| Length/rhythm | A prose sentence over 120 UTF-16 units or 3 adjacent prose sentences with identical clause-count/ending patterns; aggregate into one informational pattern. |

For repetition, low/standard/high sensitivities require 4/3/2 occurrences respectively; off disables that rule family. Exclude universal declarative `-다` and tense markers alone from repeated-ending warnings. New project-profile defaults are standard repetition and low dialogue style sensitivity; preserve explicitly decoded existing values, including the current core initializer's standard dialogue value. Settings can disable dialogue style analysis. Correctness candidates remain separately governed. Rhetorical repetition can always be dismissed or marked intentional. These defaults are product choices to review and pin with positive/negative Korean fixtures, not measured quality claims.

## Durable profile and suppression semantics

Use a versioned project-owned `UserData` record under the safe key `writing-style-profile`. It wraps the existing `WritingStyleProfile` fields, optional language/dialogue overrides and anchored intentional occurrences. Missing data yields documented defaults. Decode older value-only profiles with defaults for new fields. Normalize learned-word comparisons without changing original text or its offsets. Unknown/corrupt versions are preserved and surfaced; never overwrite them with an empty profile as a side effect of reading.

Distinguish actions clearly:

- Dismiss: presentation-only for this finding/session.
- Mark intentional: persist a rule-plus-anchored-occurrence suppression, not a story fact. Changed or ambiguous source cannot silently suppress unrelated prose.
- Disable this rule: persist its ID in the project profile's `ignoredRuleIDs`.
- Learn word: persist the exact normalized lexical entry for this project and suppress matching correctness findings; do not infer a character/world fact or globally change the macOS dictionary.

Write only through the existing runtime-identity-gated `updateUserData` path and autosave/recovery machinery. A stale action cannot update another project. Generic project/storage code sees bytes, not Korean/Fiction types. Reindexing derived Intelligence cannot delete these choices. Profile changes reanalyze affected windows or schedule an explicit global restyle, without mutating the manuscript or creating a second document owner.

## Presentation and explicit edits

Preserve the approved opaque manuscript, Noto Serif KR body, Pretendard UI and current palette. Render only eligible correctness marks as subtle, palette-aware underlines owned by a diagnostic decoration layer. Never write diagnostic attributes into saved Markdown or overwrite author formatting, cursor-line highlight, search/selection or Ghost rendering.

Group related style/rhythm/vocabulary findings in Living Margin with the original phrase, a plain-language reason, alternatives when justified and explicit actions. Do not open the panel or move focus as a side effect of analysis. Opening it must not start NLP or LLM work. Empty output stays quiet. Accessible labels convey the category and actions without relying on color.

An explicit correction validates active identity, current source text/revision, exact target span, expected original text, current map and absence of marked text. Apply one replacement through the established native editing/serialization path as one undoable edit. Recompute diagnostics through the normal change event. Undo/Redo restores text/formatting exactly; it does not reload the whole document or bypass autosave.

Stale, ambiguous, formatted-crossing or composition-overlapping replacements are refused and scheduled for recheck. Applying a safe replacement returns focus to the same editor and adjusts the caret predictably. Diagnostic controls do not intercept editor Tab/right-arrow/Escape Ghost semantics. No automatic replacement or unsolicited sentence rewriting is allowed.

The full-document API supplies the same findings, coverage/progress and cancellation to #114 Review. #126 is not a substitute Review UI. First diagnostic margin wiring advances #270 without claiming its later story/LLM producers are complete. Contextual alternatives and sentence rewrites remain distinct explicit local-model actions; they must not be hidden prerequisites for basic proofreading.

## Failure and resource behavior

Provider failures are isolated by the existing engine, but the controller tracks failed/unavailable coverage so an empty result is not a success claim. Resource mismatch, unsupported language, memory pause and corrupted profile each have a compact actionable status outside the typing flow. Preserve the previous valid manuscript/profile and allow writing/search/export throughout.

Bound analysis/result caches by bytes and active document; clear reconstructible entries under pressure. Results and logs must not persist manuscript excerpts, learned words or prompts in support diagnostics by default. No telemetry, cloud proofreading, automatic weight download or production test hook is introduced.

## Validation and delivery boundaries

New behavior receives failing regressions before implementation. Keep the existing diagnostic, project-runtime, Ghost, media/math, search, serialization and recovery tests intact. Required evidence includes:

1. **Real backend:** reproducible pinned-resource loading, notices, architecture/ABI checks and actual morphology/typo/spacing fixtures, separately from fixture-provider orchestration tests.
2. **Language quality:** inflected ending families, particles versus homographic word fragments, causal redundancy, intentional repetition, dialogue/dialect, learned names, mixed scripts, decomposed Hangul and ambiguous substitutions that must remain quiet.
3. **Coordinates and edits:** duplicate quotes, emoji, formatting inside words, headings/lists, fenced code, inline/display math and media; exact mapped marks; stale-result refusal; byte-exact Markdown/media/math round-trip and correction Undo/Redo.
4. **Ownership/persistence:** edit bursts, uncancellable late providers, local/full-report races, project A -> B -> A, profile changes, relaunch/reindex/backup restore and corrupt/unknown profile preservation.
5. **Scheduling:** a single edit in 100k/300k text and a huge single paragraph touches bounded input; unchanged windows hit cache; foreground Ghost/typing, marked text, thermal/low-power and memory-pressure events stop further admission.

Measure cold/warm native latency, peak memory, chunk duration, cancellation-to-no-further-work latency and decoration cost with pinned synthetic fixtures. The first backend-validation unit records the baseline and fixes regression budgets before production integration. The implementation plan must make that a promotion gate; it must not invent measurements in advance. Never relax existing CI/performance gates or imply calculation timings prove actual paint/IME feel.

Run appropriate `swift build`, `swift test`, `swift build --product MINTBench`, clean bundle/resource/signature validation and all required PR/main CI for implementation PRs. Native harness tests use `CFFIXED_USER_HOME` and synthetic data. Batch local actual-app/UI verification after implementation as required by the current guide; final IME/VoiceOver/visual checks identify one candidate under #119. Developer bundle evidence is not Store signing/submission proof.

The implementation plan will divide this design into independently reviewable units: native-backend validation, projection/ownership, durable profile, language rules, scheduling, editor/margin integration and full-report contracts. No code/dependency install begins from this document alone. Written-spec review precedes the detailed plan; the preserved execution method is sequential inline work with no subagents and green-CI merge authorization.

## Written review checklist

- Does the spelling-versus-style distinction match the desired writing experience?
- Are the proposed automatic-analysis, repetition and dialogue defaults appropriate?
- Are project-scoped learned words/intentional choices and explicit correction semantics correct?
- Are the native-backend gate, bounded work and coordinate-proof requirements sufficient?
- Does this deliver the first functional proofreading slice while keeping every expanded-release feature in #158 tracked?
