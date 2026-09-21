<div align="center">

# MINT

**A local writing environment that understands your story without ever taking it over.**

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
<!-- <img src="docs/assets/hero.png" width="860" alt="The MINT editor with a Living Margin insight"> -->

</div>

---

## The problem

Long-form fiction outgrows the writer's working memory before it outgrows the page.

By chapter thirty you are managing a cast who each know different things, a timeline that runs
in two directions, threads you opened and have not closed, and a hundred small facts you
established once and now have to honour. No editor helps with this. Most AI writing tools do
something else entirely: they offer to write the next paragraph for you.

MINT takes the other job. It reads what you have written, keeps track of it, and stays quiet
until the moment it has something worth saying.

Everything runs on your Mac. No manuscript leaves the machine.

---

## Principles

|  | |
| :-- | :-- |
| **Editor first** | It has to be a good writing app with the AI switched off. |
| **Quiet AI** | When confidence is low, showing nothing is the correct output. |
| **Local only** | Manuscript and inference stay on your Mac. No remote calls, no telemetry. |
| **User Canon wins** | What you decided always outranks what the model inferred. |
| **Evidence first** | A warning that matters must lead back to real text in your manuscript. |
| **Rebuildable intelligence** | Derived understanding is a cache. Your words and your decisions are not. |
| **Flow over spectacle** | Prefer the UI that interrupts the sentence less. |

The goal is not a chat panel bolted to the side of a document. It is intelligence that appears
only when it is needed and disappears when it is not.

---

## The writing experience

MINT 0.2.0 is a **writing platform, fiction first**. Fiction is the domain it goes deepest on;
it is not the only thing the app can do. Both modes sit on one project foundation.

### Fiction — `Write · Map · Review`

**Write** is where the manuscript lives.

- A native macOS editor built on TextKit, tuned to stay out of the way
- Ghost Completion that respects the Hangul IME and never fires mid-composition
- Local autocomplete that draws on the project, not just the paragraph
- A Living Margin that surfaces only when there is something to surface
- `⌘K` to ask the whole project a question

**Map** looks at the work as a story rather than a folder of files.

```
Scenes · Events · Characters · Relationships · Timeline
Story Threads · World & Object State · Research & Ideas
```

Map is not a database that replaces your manuscript. Everything the model builds is a
*projection* of the text, and anything you confirm yourself becomes the reference the
projection must respect.

**Review** collects what is worth a second look, rather than rewriting sentences for you.

- Prose quality and unintentional repetition
- Continuity across setting, cast, time and relationships
- Foreshadowing and threads still left open
- The passage in your manuscript that triggered each one
- `Intentional` · `Dismiss` · or fix it yourself

### General Writing — `Write · Outline · Review`

A standalone experience that does not depend on fiction types: document-centric navigator,
outline, writing quality, research and reference notes, Ghost Completion, Ask MINT, search
and export.

Fiction going deep must not turn general writing into "novel mode with the features removed."

---

## One project, one context

```
WritingProject
├─ mode: Fiction | General
├─ Documents
├─ Notes
├─ Assets
├─ User Canon
└─ Intelligence
```

Shared platform underneath, domain intelligence layered on top:

```
Writing Platform            Writing Intelligence      Fiction Intelligence
├─ Project Navigator        ├─ Context Retrieval      ├─ Scene · Event · Character
├─ Editor                   ├─ Living Margin          ├─ Timeline · Relationships
├─ Search / Export          └─ Review                 ├─ Object State
├─ Ask MINT                                           ├─ Story Threads
├─ Ghost Completion                                   ├─ Hierarchical Story Memory
└─ Local AI Runtime                                   ├─ Continuity
                                                      └─ Story Map
```

This is why MINT can add fiction depth without forcing novel-shaped features onto a memo.

---

## How the intelligence behaves

### Ghost Completion

Pause for a moment and a suggestion appears in grey, inline, where the cursor already is.

| Key | Action |
| :-- | :-- |
| <kbd>Tab</kbd> | Accept all |
| <kbd>→</kbd> | Accept part |
| <kbd>Esc</kbd> | Dismiss |

Prediction holds the highest execution priority in the app. Background understanding yields to
it immediately, and nothing in the prediction hot path is allowed to touch the disk, call a
retrieval model, or rebuild an index.

### Living Margin

No underlines on every sentence. No popups. A margin that stays empty until it has something
like this:

> *This character does not know that yet — they were not in the scene where it happened.*
>
> *This thread has not appeared in eleven chapters.*
>
> *The last four paragraphs end on the same rhythm.*

If confidence is low, the margin stays empty. That is a feature.

### Ask MINT

Not a permanent sidebar. `⌘K` opens a question against the current project, answers it, and
gets out of the way. When the answer asserts something about the manuscript, it should be able
to point at the passage it came from.

---

## Story memory

A novel does not compress into one large summary without losing the thing that matters.

```
Work
└─ Part / Arc
   └─ Chapter
      └─ Scene
         └─ Atomic Story Knowledge
            ├─ Event              ├─ Character State
            ├─ Fact               ├─ Character Knowledge
            ├─ Relationship State ├─ Object State
            └─ Story Thread
```

Summaries are a **retrieval router, not a source of truth**. Any judgement shown to the writer
must be traceable down to real evidence in the text.

Fiction time is not one axis either:

- **Discourse position** — the order the reader encounters it
- **Story time** — the order it happened in the world

When the time is unknown it stays unknown. The model does not get to invent a gap and then
raise a contradiction about it.

---

## Your manuscript is yours

Data precedence, highest first:

```
User Canon  >  explicit manuscript text  >  deterministic inference
            >  agent inference  >  summary
```

Character sheets you corrected, relationships you fixed, contradictions you marked intentional:
reanalysis never overwrites these. Summaries, extractions and search indexes are all
disposable and can be rebuilt from the text.

On disk:

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

---

## Status — 0.2.0

0.2.0 is under active development. This table is a summary; the authoritative scope, sequence
and gates live in
[**Epic #99**](https://github.com/sorbetsharkroundhand/MINT/issues/99).

| Area | State |
| :-- | :-- |
| Native editor, Ghost Completion, search, export | Working |
| Project domain, store and non-destructive migration | Working |
| Fiction / General workspace routing and shell | Working |
| Living Margin framework | Landed, presentation in progress |
| Hierarchical story memory | Landed, retrieval integration in progress |
| Writing Quality core | Working, Korean rule set in progress |
| Ask MINT, Story Map, Review surface | In progress |
| Project-first runtime handoff ([#118](https://github.com/sorbetsharkroundhand/MINT/issues/118)) | In progress |
| App Store distribution path ([#150](https://github.com/sorbetsharkroundhand/MINT/issues/150)) | In progress |

> **Reading the code:** the primary editor flow still runs through the legacy `EntryStore`
> compatibility path while [#118](https://github.com/sorbetsharkroundhand/MINT/issues/118)
> completes the project-first runtime handoff. Some 0.2.0 workspace UI therefore exists in the
> source without appearing in the normal document flow yet. Replacement surfaces land before
> any legacy UI is retired.

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

</details>

<details>
<summary><strong>Verification</strong></summary>

<br>

```bash
swift build
swift test
swift build --product MINTBench

scripts/build-mint-app.sh
scripts/smoke-mint-app.sh
scripts/ui-smoke-mint-app.sh
```

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
| [Design specification](docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md) | 0.2.0 design contract |
| [Epic #99](https://github.com/sorbetsharkroundhand/MINT/issues/99) | Release scope, sequence and gates |

Historical plans and benchmark reports under `docs/` record their original contracts. They are
not current implementation contracts — read them to answer a specific question, not to learn
how the code works today.

---

## License

Source available, all rights reserved. See [LICENSE](LICENSE).

You may read this source and build it locally to evaluate MINT. You may not redistribute it,
publish modified versions, or use it commercially. Licensing and commercial terms are being
finalised in [#155](https://github.com/sorbetsharkroundhand/MINT/issues/155) and may change.

---

<div align="center">

When MINT is working, you should not be aware you are using AI at all.

You write. MINT reads behind you, remembers what matters, speaks only when it should,
finds the evidence when you ask, keeps every decision you made,

and never behaves as though it knows the story better than you do.

<br>

**The writer owns the story. MINT helps them keep hold of it.**

</div>