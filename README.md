<div align="center">

# MINT

**A local, editor-first writing app. Fiction first; useful without AI.**

*The writer owns the story. MINT helps them keep hold of it.*

<br>

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-111111?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)
![Inference](https://img.shields.io/badge/inference-100%25%20local-2ea44f?style=flat-square)
[![CI](https://github.com/sorbetsharkroundhand/MINT/actions/workflows/ci.yml/badge.svg)](https://github.com/sorbetsharkroundhand/MINT/actions/workflows/ci.yml)
![License](https://img.shields.io/badge/license-Source%20Available-4c1?style=flat-square)

<br>

<!-- TODO: replace with a real screenshot or a short GIF of Ghost Completion in action.
     A writing app README without a picture of the writing surface is doing itself a disservice. -->
<!-- <img src="docs/assets/hero.png" width="860" alt="The MINT writing editor"> -->

</div>

---

## The problem

Long-form fiction outgrows the writer's working memory before it outgrows the page.

By chapter thirty you are managing a cast who each know different things, a timeline that runs
in two directions, threads you opened and have not closed, and a hundred small facts you
established once and now have to honour. Writing still needs to feel like writing, not like
managing an AI setup or a separate database of your story.

MINT's first-release goal is a dependable place to create, import, write, save, search original
sources and export, with optional local assistance. Fiction is the deepest first-release domain;
General writing and AI-disabled editing remain supported paths.

Everything runs on your Mac. No manuscript leaves the machine.

---

## Principles

|  | |
| :-- | :-- |
| **Editor first** | It has to be a good writing app with the AI switched off. |
| **Quiet AI** | When confidence is low, showing nothing is the correct output. |
| **Local only** | Manuscript and inference stay on your Mac. No remote inference, no telemetry. |
| **User Canon wins** | What you decided always outranks what the model inferred. |
| **Evidence first** | A warning that matters must lead back to real text in your manuscript. |
| **Rebuildable intelligence** | Derived understanding is a cache. Your words and your decisions are not. |
| **Flow over spectacle** | Prefer the UI that interrupts the sentence less. |

The goal is not a chat panel bolted to the side of a document. It is intelligence that appears
only when it is needed and disappears when it is not.

---

## First-release scope

The **first Mac App Store release is under development**. The scope below is a release contract,
not a claim that every path is complete or that this checkout is Store-ready.
[Epic #99](https://github.com/sorbetsharkroundhand/MINT/issues/99) owns scope and sequence;
[gate #119](https://github.com/sorbetsharkroundhand/MINT/issues/119) owns readiness for one
identified release candidate.

### Write first — Fiction and General

- Create or import a manuscript, edit it, save and recover it, find original source text, and export.
- No model or network setup is required for that writing workflow.
- Fiction and General use the same project runtime; generic project and storage code stay
  independent of Fiction types.
- Preserve Hangul IME, selection, undo, writing position, and Markdown/EPUB/media/math round-trip.

### Optional local Ghost Completion

When enabled, Ghost offers suggestions in grey, inline, where the cursor already is.

| Key | Action |
| :-- | :-- |
| <kbd>Tab</kbd> | Accept all |
| <kbd>→</kbd> | Accept part |
| <kbd>Esc</kbd> | Dismiss |

Ghost is optional and local. Cursor-bounded completion must exclude future knowledge, and no
Ghost is generated during marked IME text. Background work yields to foreground prediction;
the prediction hot path must not scan disk, call a retrieval model, or rebuild an index.

### Source search, not generated answers

The first-release search contract is deterministic, model-free manuscript search with a way to
open the supporting passage and return to writing
([#108](https://github.com/sorbetsharkroundhand/MINT/issues/108)). The planned `⌘K` flow
([#112](https://github.com/sorbetsharkroundhand/MINT/issues/112)) is source inspection, not a
promise of LLM-generated Ask MINT answers or a permanent chat sidebar. These integrations are
still release work, not completed features inferred from UI scaffolding.

---

## Your manuscript is yours

Data precedence, highest first:

```
User Canon  >  explicit manuscript text  >  deterministic inference
            >  agent inference  >  summary
```

The release must preserve manuscripts and explicit writer decisions across reindexing,
relaunch and recovery. Derived summaries, extractions and indexes are rebuildable; they must
not replace original evidence or overwrite writer decisions. Durable project-owned writer data
is tracked in [#111](https://github.com/sorbetsharkroundhand/MINT/issues/111), not claimed complete
by the existence of an Intelligence cache.

Current developer project layout:

```
~/Documents/MINT/Projects/<project-id>/
├─ project.json
├─ Documents/
├─ Notes/
├─ Assets/
└─ Intelligence/
```

Migration from the older `entries.json` layout is **non-destructive by contract**. The original
is never transformed in place, and a new project is verified before it is ever activated.
Storage roots are centralized in `MintStorageLocation`; this developer layout is not proof of
the final sandbox/container migration or Store distribution path.

---

## Status — first Mac App Store release

Existing foundations and remaining release work are separate. The current issue bodies in
[Epic #99](https://github.com/sorbetsharkroundhand/MINT/issues/99) take precedence over this summary.

| Area | State |
| :-- | :-- |
| Native editor, Ghost Completion, document search and export | Existing foundations; integrated release verification remains |
| Project domain, store and non-destructive migration | Existing foundations; runtime ownership remains [#118](https://github.com/sorbetsharkroundhand/MINT/issues/118) |
| Recovery and durable writer data | Required release work: [#151](https://github.com/sorbetsharkroundhand/MINT/issues/151), [#111](https://github.com/sorbetsharkroundhand/MINT/issues/111) |
| Model-free project source search | Required release work: [#108](https://github.com/sorbetsharkroundhand/MINT/issues/108), [#112](https://github.com/sorbetsharkroundhand/MINT/issues/112) |
| Model lifecycle and Store distribution | Required release work: [#152](https://github.com/sorbetsharkroundhand/MINT/issues/152), [#150](https://github.com/sorbetsharkroundhand/MINT/issues/150) |
| General/no-model, native UX and product decisions | Owner verification/decisions: [#116](https://github.com/sorbetsharkroundhand/MINT/issues/116), [#153](https://github.com/sorbetsharkroundhand/MINT/issues/153), [#155](https://github.com/sorbetsharkroundhand/MINT/issues/155) |

> **Reading the code:** the primary editor flow still runs through the legacy `EntryStore`
> compatibility path while [#118](https://github.com/sorbetsharkroundhand/MINT/issues/118)
> completes the project-first runtime handoff. Code or hidden UI is not evidence of a shipping
> feature. User data must remain accessible when legacy UI is retired.

Green unit tests or an ad-hoc developer bundle do not establish Store readiness. Signing,
sandbox/archive checks, quality evidence and owner/manual checks must all refer to the same
candidate under [#119](https://github.com/sorbetsharkroundhand/MINT/issues/119).

### Post-release — not first-release promises

- Map and Review breadth, including broad story projections and review dashboards.
- LLM-generated Ask MINT answers, Living Margin suggestion generation, and Writing Quality UI.
- Advanced Story Intelligence ([#158](https://github.com/sorbetsharkroundhand/MINT/issues/158)).
- Generalized prompt-state reuse beyond the release topology
  ([#149](https://github.com/sorbetsharkroundhand/MINT/issues/149)), presentation/motion/state
  consolidation ([#163](https://github.com/sorbetsharkroundhand/MINT/issues/163)), and math-atom
  extraction ([#165](https://github.com/sorbetsharkroundhand/MINT/issues/165)).

Existing frameworks or experiments for these capabilities do not make them first-release features.

---

## Technology

| Area | Stack |
| :-- | :-- |
| Language | Swift 6 |
| Platform | macOS 14+, Apple Silicon |
| UI | SwiftUI + AppKit / TextKit |
| Local inference | Apple MLX — `mlx-swift`, `mlx-swift-lm` |
| Tokenizer / Hub | `swift-transformers`, `swift-huggingface` |
| Math rendering | SwiftMath |
| Package manager | Swift Package Manager |
| Tests | XCTest, plus app launch and UI smoke |

The editor and the domain model are deliberately kept independent of any single model provider,
and of fiction-specific types wherever that coupling is not required.

---

## Run from source

**Requirements** — Apple Silicon Mac · macOS 14+ · Xcode 16+ · Swift 6 toolchain

These are development prerequisites, not final supported-model/hardware claims. Release support
and licensing decisions remain subject to [#152](https://github.com/sorbetsharkroundhand/MINT/issues/152)
and [#155](https://github.com/sorbetsharkroundhand/MINT/issues/155).

SwiftPM builds the executable, but MLX also needs its Metal shader library.

```bash
git clone https://github.com/sorbetsharkroundhand/MINT.git
cd MINT

scripts/prepare-metallib.sh
swift run MINT
```

`prepare-metallib.sh` caches its output and rebuilds only when the pinned `mlx-swift`
revision changes.

<details>
<summary><strong>Building a local <code>.app</code></summary>

<br>

Closer to the lifecycle CI actually exercises:

```bash
scripts/build-mint-app.sh
open build/MINT.app
```

The script prepares `mlx.metallib`, builds the release executable, assembles
`build/MINT.app` and applies an ad-hoc signature for local execution.
It does not produce an App Store-validated distribution artifact.

</details>

<details>
<summary><strong>Verification</strong></summary>

<br>

```bash
swift build
swift test
swift build --product MINTBench

scripts/build-mint-app.sh
```

Required CI retains build, deterministic correctness, launch and sandbox checks.
Local actual-app/UI tests are batched after implementation on one identified
candidate; `scripts/ui-smoke-mint-app.sh` is an owner-triggered native check,
requiring Accessibility permission. Real IME/Ghost/VoiceOver and interaction
quality remain owner verification. See the [verification/support contract](docs/release/verification-and-support.md).

</details>

---

## Repository map

```
Sources/
├─ MINT/                     @main application shell (thin)
├─ MINTCore/
│  ├─ Project/               WritingProject, ProjectStore, ProjectSession
│  ├─ Workspace/             shell, routing, navigator presentation
│  ├─ Onboarding/            first run, project creation and import
│  ├─ Editor/                TextKit editor, Ghost Completion, math, images
│  ├─ Inference/             MLX runtime, completion, context assembly
│  ├─ Knowledge/             story understanding, retrieval, evidence anchors
│  ├─ Intelligence/          Living Margin
│  ├─ WritingQuality/        provider-independent diagnostics
│  ├─ Media/                 image references, asset lifecycle
│  ├─ Storage/               entries, images, trash, writing position
│  ├─ Export/                Markdown and EPUB
│  └─ Components/            shared view components
└─ MINTBench/                quality and latency benchmark CLI

Tests/
└─ MINTCoreTests/            deterministic regression coverage
```

## Documentation

| Document | What it is |
| :-- | :-- |
| [PLAN.md](PLAN.md) | Architecture and context index |
| [AGENTS.md](AGENTS.md) | Shared invariants and verification commands |
| [Historical design specification](docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md) | Former 0.2.0 breadth; not the current release contract |
| [Epic #99](https://github.com/sorbetsharkroundhand/MINT/issues/99) | Release scope, sequence and gates |
| [Gate #119](https://github.com/sorbetsharkroundhand/MINT/issues/119) | Evidence and owner checks for one identified release candidate |

Historical plans and benchmark reports under `docs/` record their original contracts. They are
not current implementation contracts — read them to answer a specific question, not to learn
how the code works today.
Old inline `CLAUDE.md §N` / `PLAN §N` citations are historical references, not current requirements.

---

## License

Source available, all rights reserved. See [LICENSE](LICENSE).

You may read this source and build it locally to evaluate MINT. You may not redistribute it,
publish modified versions, or use it commercially. Licensing and commercial terms are being
finalised in [#155](https://github.com/sorbetsharkroundhand/MINT/issues/155) and may change.

---

<div align="center">

A dependable place to write, with optional local help and original evidence you can inspect.

<br>

**The writer owns the story. MINT helps them keep hold of it.**

</div>
