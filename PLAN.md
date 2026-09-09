# MINT — Architecture & Implementation Plan

> **Writing Platform, Fiction First.**
>
> Core rule: **background work prepares understanding; foreground prediction only assembles prepared context and generates.**

This is the compact canonical architecture/roadmap. Historical experiment logs belong in issues/PRs/docs, not here. See `AGENTS.md` for invariants and the 0.2.0 spec/plans under `docs/superpowers/`.

## Current 0.2.0 status — 2026-09-08

Release membership should be tracked by the GitHub milestone **MINT 0.2.0**; #99 is the product contract, dependency map, and main-merge ledger.

- ✅ #100 Gate 0 / PR #121 — green CI baseline.
- ✅ #101 / PR #122 — generic WritingProject/WritingDocument domain.
- ✅ #102 / PR #123 — ProjectStore + non-destructive legacy migration.
- ◐ #103 — shell baseline + Navigator drag-collapse + persistent tool docking + titlebar geometry landed via PR #124/#130/#132/#138; final real-macOS visual/IME/Ghost/Reduce Transparency verification remains.
- ✅ #104 — mode-aware Write/Map/Review vs Write/Outline/Review routing: project/session foundation PR #135 + live shell/focus/persistence/UI-smoke completion PR #142.
- ✅ #125 / PR #128 — wrapped Ghost geometry regression fixed on main.
- ◐ #126 — provider-independent cancellable Writing Quality core merged via PR #133; Korean morphology provider/rules + packaging/licensing/perf follow.
- ◐ #18 — visible media scan bounded via PR #139; dirty-edit paragraph/block index + 300k/100-media evidence remain.
- ✅ #61 retired after re-audit: useful PR1–5 retained; PR6–9 superseded by #103/#113/#117.
- ◐ #119 — final release gate; warning/CI infrastructure landed via PR #129/#137/#140/#141, but RC long-document/product/E2E matrix remains open.

---

## 1. Vision and deliberate departures from common AI editors

MINT supports General Writing and deep Fiction Intelligence. The target Fiction experience is a **remembering co-writer**:

- remembers characters, relationships, events, world state, style, and timeline;
- preserves consistency across long manuscripts;
- grows its understanding in the background;
- remains useful when AI is disabled.

Default architectural choices:

| Common pattern | Why it is weak on-device / for fiction | MINT |
| --- | --- | --- |
| Whole-manuscript giant context | linear prefill cost, heat/battery, weak middle recall | recent text + hierarchical/structured memory |
| Generic vector RAG first | fiction relevance is entity/causal, not just semantic similarity | structure-first retrieval; semantic fallback |
| Agent chain at prediction time | too slow for Ghost UX | multi-step reasoning in background only |
| One rolling summary | destroys temporal state and leaks future knowledge | versioned state/evidence + hierarchical summaries |

Seven conceptual memory views do **not** require seven independent stores. MINT keeps a smaller set of durable structures and exposes multiple query views over them.

---

## 2. Product decisions

| Area | Decision |
| --- | --- |
| Product | Native macOS app, Apple Silicon |
| Root domain | `WritingProject` with `WritingMode.general / .fiction` |
| Editor UX | inline Ghost: `Tab` accept, `→` partial, `Esc` reject |
| AI | local MLX only; master switch can disable |
| Context | recent manuscript + prepared structured knowledge |
| Durable data | manuscript + project metadata + User Canon |
| Rebuildable data | summaries, indexes, extracted Intelligence |
| Storage transition | verified new project before activation; legacy source untouched |
| Prediction modes | Fast / Smart / Story |
| Visual system | opaque Editorial Surface + selective Liquid Glass chrome/intelligence |
| Writing Quality | local correctness/style/vocabulary diagnostics; Korean morphology first; multilingual provider boundary |

### Liquid Glass contract

- Editor body: opaque.
- Navigator document list: opaque/tinted.
- Navigator header/search + toolbar/titlebar: restrained Liquid Glass.
- Docked tool panel: flatter restrained material.
- Floating tool panel / Ask MINT: elevated Liquid Glass.
- Living Margin canvas: quiet/flat; transient insight may use selective material.
- Never stack glass container → glass card → glass button.

---

## 3. Tech stack and constraints

- Swift 6, SwiftUI, AppKit/TextKit.
- MLX / mlx-swift-lm local inference.
- Swift Package Manager.
- SwiftMath for math rendering.
- macOS 14+ target, Apple Silicon.
- Hangul IME safety is release-critical.
- `swift build` is a compile/type check; runtime MLX may require metallib preparation.
- Use one resident model/engine. Do not duplicate model loads for background work.

### Model presets

Current product naming is personality-oriented rather than size-tier-oriented:

- **MINT** — ternary dense model; not the default after measured latency.
- **Basil** — current recommended/default path for new users based on measured warm reuse/TTFC.
- **Peppermint** — alternative MoE profile.

Exact model IDs/sizes belong in Settings > Advanced and benchmark evidence, not primary onboarding UI.

---

## 4. Architecture — three planes

```
Document plane (source of truth)
  Editor / BlockTextView
  EntryStore compatibility
  WritingProject / WritingDocument

Knowledge plane (rebuildable)
  BackgroundIndexer
  hierarchical summaries
  atomic/temporal Story Knowledge
  indexes / NarrativeGraph
  continuity candidates

Inference plane
  CompletionController
  ContextAssembler
  CompletionEngine (single resident model)
  Ask MINT / Agent Judge

Writing Quality (independent, local)
  incremental diagnostics engine
  system spell/grammar provider
  Korean morphology provider (Kiwi candidate behind adapter)
  WriterStyleProfile / learned words
```

Three paths:

1. **Write path** — synchronous and tiny: edit → invalidate hashes/dirty scope. No LLM/disk scan.
2. **Understand path** — idle/background: extract/derive → update sidecar/indexes.
3. **Predict path** — debounce → eligibility → assemble prepared context → one foreground generation.

Foreground prediction may cancel/preempt background inference.

---

## 5. Document, project, storage, and workspace

### 5.1 Generic project domain (#101)

`WritingProject` is generic and owns stable IDs, title, mode, and ordered documents. `WritingDocument` owns stable ID, title, body, and kind.

Rules:
- General types do not depend on Fiction types.
- Stable IDs survive edits/serialization.
- Derived scene hashes are never persistent document IDs.
- Legacy adaptation preserves body bytes/string exactly.

### 5.2 ProjectStore and non-destructive migration (#102)

Target shape:

```
Projects/<project-id>/
├─ project.json
├─ Documents/
├─ Notes/
├─ Assets/
├─ UserData/
└─ Intelligence/
```

Safety contract:
- `entries.json` is read-only migration input.
- Write the new project separately.
- Verify content/metadata/assets before activation.
- Activation is the final atomic step.
- Keep recovery metadata/previous valid state.
- Reject path traversal and symlink escape.
- Deleting `Intelligence/` must not affect user content.
- User Canon is durable project data, not sidecar cache.

### 5.3 Current editor/outline model

- Markdown headings deterministically provide structural outline hints.
- Large heading-less content may be segmented for analysis, not rewritten in the manuscript.
- Content hashes and stable anchors drive dirty tracking.
- Evidence always resolves back to original text before user-facing claims.

### 5.4 Document-centric App Shell (#103)

`WorkspaceShellView` owns layout, not storage or Knowledge logic.

Current/target:
- persistent Project Navigator;
- opaque editor;
- user-controlled tool/context surface;
- titlebar/traffic-light safe region has one source of truth;
- divider can drag through a collapse threshold and restore last width;
- tool dock preference: `automatic / left / right / bottom / floating`;
- temporary narrow-window fallback never overwrites the preference;
- docking/collapse preserves editor first responder, IME, Ghost, cursor-line highlight.

### 5.5 Writing Quality (#126)

Writing Quality is a common platform capability for General and Fiction. It does **not** depend on Story Intelligence.

Categories:
- **Correctness** — spelling, spacing, grammar.
- **Style** — repeated words/particles/endings/connectors, redundant causality, connective-chain depth, sentence starts/length/rhythm.
- **Vocabulary** — vague/overused words and explicit word/phrase alternatives.

Korean v1 must compare morphological **function/family**, not only surface strings. Kiwi is the leading morphology candidate because upstream exposes native Swift/macOS bindings, sentence splitting, token/POS positions, typo support, and user dictionaries. Shipping it requires a separate Swift 6/macOS packaging, resource-size, performance, and LGPL-compliance gate. The generic API must not expose Kiwi types.

Scheduling:
```
edit → debounce/idle → dirty sentence/paragraph analysis → generation-scoped publish
```

Rules:
- no whole-document work per keystroke;
- no disk read or LLM call in the typing diagnostics hot path;
- Ghost has higher priority;
- edit/project switch cancels stale diagnostics;
- vocabulary/rephrase model calls happen only after explicit user action;
- `WriterStyleProfile` owns learned words, ignored rules, repetition/dialogue sensitivity, and intentional style patterns;
- WriterStyleProfile is not #111 User Canon.

Presentation ownership:
- #117: only high-confidence correctness may use subtle inline marks;
- #105: local style/rhythm/vocabulary in Living Margin;
- #114: document/project-wide Writing Quality report;
- avoid dense multi-color underline saturation.

---

## 6. Knowledge store — hierarchical memory

Conceptual views map onto fewer structures:

- live recent-text window;
- Scene → Chapter → Work summary pyramid;
- entity/state Story Knowledge;
- event log + timeline indexes;
- style profile;
- NarrativeGraph/read projections.

### 6.1 Summary pyramid

- Scene summary → Chapter summary → Work summary.
- Dirty propagation only follows changed descendants.
- Unchanged siblings are not recomputed.
- Summaries route retrieval; they are never final truth.
- User-facing claims drill down to original evidence.

### 6.2 Story Knowledge

Atomic items include:
- Event
- Fact
- CharacterState
- CharacterKnowledge
- RelationshipState
- ObjectState
- StoryThread

Each item carries:
- evidence;
- confidence/origin;
- discourse position;
- optional story time.

Unknown story time remains unknown.

### 6.3 Event/state history

State changes are append/version oriented so `state_at(position)` can reconstruct what was true at a cursor-bounded point.

### 6.4 Style

Style is global + character/dialogue aware. It informs ranking/generation but cannot override explicit manuscript text or User Canon.

### 6.5 Evidence contract

`EvidenceAnchor` carries document identity + quote + hints. Existing `SourceAnchor` remains the resilient matching utility.

Truth priority:

```
User Canon
> explicit manuscript text
> deterministic inference
> Agent inference
> summary
```

### 6.6 Narrative Graph

NarrativeGraph is a derived read projection over evidence-backed events/threads/relations. 0.2.0 does not require a full editable graph authoring system.

---

## 7. Character system

Character understanding combines deterministic structure + model extraction.

Rules:
- auto-create only high-confidence candidates with strong structural signals;
- medium/ambiguous candidates require user confirmation;
- aliases/merges are user-confirmed;
- character knowledge is temporal: a character cannot use a fact before acquisition;
- user correction/Intentional becomes durable User Canon;
- character cards are evidence-backed and rebuildable except user-owned edits/canon.

---

## 8. Timeline system

Keep two axes:

- **discourse order** — where text appears in the manuscript;
- **story time** — when the event happens in-world.

Never infer hard temporal conflicts from unknown story time.

Continuity examples:
- impossible location overlap only when time is comparable;
- age/time arithmetic only from explicit facts;
- destroyed object reappearance requires a restore transition or is a candidate;
- flashback/quotation must not become false-positive continuity errors.

---

## 9. Background understanding pipeline

Trigger during idle/background windows, not keystroke hot path.

```
dirty scene/document
→ deterministic parse/hash
→ extract/derive
→ update Story Knowledge / summaries / indexes
→ publish generation-scoped snapshot
```

Requirements:
- cancellable;
- project/generation scoped;
- no stale publication;
- thermal/low-power aware when expensive;
- memoized by content hash;
- yields to Ghost prediction;
- incremental rebuild by default.

---

## 10. Prediction pipeline

Gate order is an invariant:

```
master enabled
→ no IME marked text
→ eligible cursor/paragraph state
→ enough context
→ debounce
→ assemble prepared context
→ one foreground generation
→ Ghost
```

Rules:
- no disk I/O or retrieval LLM call in hot path;
- no future knowledge leakage;
- stale generation cannot publish;
- `Tab / → / Esc` behavior remains stable;
- Ghost overlay never mutates text storage;
- #125 fixes wrapped overlay geometry by using actual TextKit caret/line-fragment geometry.

---

## 11. Context assembly and ranking

Structure-first:

```
recent text
+ current/adjacent scene
+ exact entity/event/state evidence
+ timeline/graph hints
+ chapter/work summaries
+ local full-text
+ optional semantic fallback
+ User Canon
```

Budget degradation removes lower-value context before increasing latency.

Each user-visible retrieval candidate records why it was selected and resolves to source evidence.

Scopes:
- Here
- Chapter/Document
- Project

---

## 12. Caching and KV strategy

Latency priorities:
1. keep one model resident when appropriate;
2. reuse compatible KV/prefix state when measurements prove it works;
3. cache prepared structured context, not arbitrary stale prompts;
4. invalidate by model/settings/project/generation/content ownership;
5. prefer correctness over a risky reuse hit.

Do not claim KV benefit without MINTBench evidence.

---

## 13. Evaluation and MINTBench

Measure both quality and latency.

Required metrics by change type:
- cold/warm TTFC;
- tokens/s;
- KV reuse amount/hit rate;
- Ghost acceptance;
- typing p50/p95/max;
- visible-range render work;
- background preemption latency;
- 100k/300k memory/derive/retrieval/Map latency;
- sidecar size;
- warning precision / false-positive-sensitive continuity cases.
- Writing Quality dirty-range analysis latency and false-positive fixtures.

Performance thresholds come from measured baselines, not guessed constants.

---

## 14. Roadmap

### 0.2.0 platform
- [x] #100 CI baseline
- [x] #101 generic project domain
- [x] #102 project storage/migration
- [x] #103 shell finish — PR #146
- [x] #104 workspace routing — PR #135 + #142
- [x] #105 Living Margin — PR #147
- [x] #125 Ghost wrap regression — PR #128
- [ ] #126 Writing Quality core / Korean morphology — core merged via PR #133; provider work remains

### Story Intelligence
- [x] #106 hierarchical memory
- [ ] #107 atomic/temporal knowledge
- [ ] #108 structure-first retrieval
- [ ] #109 deterministic continuity
- [ ] #110 evidence-bounded Agent Judge
- [ ] #111 durable User Canon

### Product surfaces
- [ ] #112 Ask MINT
- [ ] #113 Story Map
- [ ] #114 Review
- [ ] #115 Story Context for Ghost
- [ ] #116 General Writing proof
- [ ] #117 Editor Diet
- [ ] #118 onboarding/import

### Release
- [ ] #18 residual media/render performance — visible path bounded via PR #139; dirty-edit index/evidence remain
- [ ] #119 release readiness — PR #129/#137/#140/#141 establish warning/CI baseline; final RC matrix remains

Canonical 0.2.0 execution plans live in `docs/superpowers/plans/`.

---

## 15. Research ideas

Only promote ideas after measurement.

Candidates:
- semantic embeddings as fallback when structure-first misses useful evidence;
- speculative/prefix/KV optimizations supported by the selected model;
- richer story-time inference with explicit uncertainty;
- better local reranking;
- optional writing modes beyond General/Fiction.

No vector DB, agent chain, or giant-context strategy is mandatory for 0.2.0.

---

## 16. Technical debt and open questions

Current blockers/risks:
- #18 paragraph/block walk + media visible-range performance evidence.
- #126 local writing diagnostics: morphology packaging/licensing, false-positive control, dirty-range performance.
- #119 final RC release matrix and warning-zero recheck; current warning/CI infrastructure is green via PR #129/#137/#140/#141.
- Complete #103 final shell visual/IME/Ghost/Reduce Transparency verification; structural window chrome landed via PR #138.
- Validate long-document background scheduling against foreground Ghost.

Open product questions should be recorded in child issues with evidence rather than expanding this file.

---

## Appendix A. Legacy `PLAN §N` anchor map

Section numbers intentionally remain stable at a high level:

- §1 vision
- §2 product decisions
- §3 stack/constraints
- §4 architecture
- §5 document/project/workspace
- §6 knowledge
- §7 characters
- §8 timeline
- §9 background understanding
- §10 prediction
- §11 context assembly
- §12 cache/KV
- §13 evaluation
- §14 roadmap
- §15 research
- §16 debt/open questions

When moving an anchored concept, update code comments in the same change.

---

## Appendix B. Key files

- `Sources/MINTCore/Editor/BlockTextView.swift`
- `Sources/MINTCore/Editor/CompletionController.swift`
- `Sources/MINTCore/Inference/ContextAssembler.swift`
- `Sources/MINTCore/Inference/CompletionEngine.swift`
- `Sources/MINTCore/Project/`
- `Sources/MINTCore/Knowledge/`
- `Sources/MINTCore/Workspace/`
- `Sources/MINTCore/Agent/`
- `Sources/MINTCore/Storage/EntryStore.swift`
- `Sources/MINTCore/Theme.swift`
- `Sources/MINTBench/main.swift`
- `.github/workflows/ci.yml`
- `.github/workflows/release-readiness.yml`

---

## Appendix C. Verification matrix

| Change | Minimum evidence |
| --- | --- |
| Any PR | `swift test`, `swift build`, clean diff/status |
| Storage/migration | failure fixtures, source hash, reopen/recovery |
| Concurrency/cancellation | deterministic fake/interleaving + stale-publication guard |
| Prediction gates | direct gate-order tests + IME coverage |
| Editor performance | MINTBench + Instruments where wall-clock/UI is relevant |
| Model/prompt | cold/warm TTFC, quality/acceptance, KV evidence |
| UI/accessibility | app bundle, keyboard-only, VoiceOver, Reduce Motion/Transparency, light/dark |
| Media/math | load→edit→serialize→reload→export→undo/redo |
| Release | isolated app/UI smoke with `CFFIXED_USER_HOME` |
