# MINT

> **A local writing environment that understands the context of what you write without taking control away from the writer.**

**MINT는 글을 대신 써 주는 AI가 아니라, 작가가 쓰고 있는 글과 세계를 이해하면서도 주도권은 끝까지 작가에게 남겨 두는 로컬 글쓰기 환경입니다.**

MINT 0.2.0의 방향은 **Writing Platform, Fiction First**입니다.

소설은 MINT가 가장 깊게 파고드는 첫 번째 전문 영역이지만, MINT 자체가 소설 전용 앱인 것은 아닙니다.  
하나의 프로젝트 기반 글쓰기 플랫폼 위에서 Fiction에는 더 깊은 이야기 지능을, General Writing에는 더 가벼운 구조·검토 도구를 제공합니다.

모든 AI 추론은 **Apple Silicon Mac 안에서 로컬로 실행**됩니다. 원고를 서버로 보내지 않고, 원격 추론이나 텔레메트리를 제품 전제로 두지 않습니다.

---

## Why MINT

대부분의 AI 글쓰기 도구는 채팅창에서 문장을 생성하거나, 사용자가 쓰기도 전에 적극적으로 개입합니다.

MINT가 원하는 경험은 다릅니다.

- **Editor first** — AI가 없어도 좋은 글쓰기 앱이어야 합니다.
- **Quiet AI** — 확신이 없으면 조용히 있는 편을 택합니다.
- **Local only** — 원고와 추론은 사용자의 Mac 안에 머뭅니다.
- **User Canon wins** — 사용자가 정한 설정과 판단은 자동 추론보다 항상 우선합니다.
- **Evidence first** — 중요한 경고는 “AI가 그렇게 생각한다”가 아니라 실제 원고 근거로 돌아갈 수 있어야 합니다.
- **Rebuildable intelligence** — AI가 이해한 지식은 다시 만들 수 있는 캐시이고, 원고와 사용자 결정은 오래 보존되는 데이터입니다.
- **Writing flow over AI spectacle** — AI를 보여 주기 위한 UI보다 글의 흐름을 덜 끊는 UI를 우선합니다.

MINT의 목표는 거대한 채팅 패널을 문서 옆에 붙이는 것이 아니라, **필요한 순간에만 나타나는 living intelligence**를 만드는 것입니다.

---

## The writing experience

### Fiction

```text
Write | Map | Review
```

**Write**는 원고를 쓰는 기본 공간입니다.

- 집중을 방해하지 않는 네이티브 macOS 에디터
- 한글 IME를 존중하는 Ghost Completion
- 프로젝트 맥락을 이용한 로컬 자동완성
- 필요한 순간에만 나타나는 Living Margin
- 프로젝트 전체를 질문하는 Ask MINT

**Map**은 작품을 “파일 목록”이 아니라 **이야기 구조**로 바라보는 공간입니다.

목표 범위는 다음을 포함합니다.

- Scene / Event
- Characters
- Relationships
- Timeline
- Story Threads
- World / Object State
- Research / Ideas
- 원고 근거로 돌아갈 수 있는 Story Map

Map은 작가의 원고를 대체하는 데이터베이스가 아닙니다.  
AI가 만든 구조는 원고를 이해하기 위한 projection이며, 사용자가 확인한 설정과 판단이 최종 기준입니다.

**Review**는 문장을 대신 고치는 화면이 아니라 **검토할 가치가 있는 것만 모아 주는 공간**을 지향합니다.

- 문장 품질과 반복
- 설정·인물·시간·관계의 연속성
- 복선과 열린 스레드
- 원문 evidence
- `Intentional` / `Dismiss` / 사용자 수정

중요한 경고일수록 반드시 원고의 실제 근거를 따라갈 수 있어야 합니다.

### General Writing

```text
Write | Outline | Review
```

General Writing은 Fiction 타입에 의존하지 않는 독립적인 글쓰기 경험입니다.

- 문서 중심 Navigator
- Outline
- Writing Quality
- Research / Reference / Ideas
- Ghost Completion
- Ask MINT
- Search / Export

Fiction이 깊은 이야기 지능을 가진다고 해서, 일반 글쓰기가 “기능이 빠진 소설 모드”가 되어서는 안 됩니다.

---

## One project, one context

MINT 0.2.0의 루트 도메인은 `WritingProject`입니다.

```text
MINT
└─ WritingProject
   ├─ mode: Fiction | General
   ├─ Documents
   ├─ Notes
   ├─ Assets
   ├─ User Canon
   └─ Intelligence
```

공유 플랫폼 위에 모드별 지능을 얹습니다.

```text
Writing Platform
├─ Project Navigator
├─ Editor
├─ Search / Export
├─ Ask MINT
├─ Ghost Completion
└─ Local AI Runtime

Writing Intelligence
├─ Context Retrieval
├─ Living Margin
└─ Review

Fiction Intelligence
├─ Scene / Event / Character
├─ Timeline / Relationship / Object State
├─ Story Threads
├─ Hierarchical Story Memory
├─ Continuity
└─ Story Map
```

이 구조 덕분에 MINT는 “소설 기능을 일반 문서에도 억지로 끼워 넣는 앱”이 아니라, 같은 글쓰기 기반 위에 필요한 도메인 지능만 선택적으로 올릴 수 있습니다.

---

## Intelligence should stay beside the writer, not above them

### Ghost Completion

MINT의 자동완성은 사용자가 문장을 작성하는 동안 전경을 빼앗지 않습니다.

글을 잠깐 멈췄을 때 회색 Ghost로 제안하고:

- `Tab` — 전체 수락
- `→` — 일부 수락
- `Esc` — 거부

를 사용합니다.

예측은 가장 높은 실행 우선순위를 가지며, 백그라운드 이해 작업은 즉시 양보해야 합니다.

### Living Margin

AI가 모든 문장에 밑줄을 긋고 팝업을 띄우는 방향을 피합니다.

Living Margin은 현재 글과 관련된 중요한 정보가 있을 때만 조용히 나타나는 공간입니다.

예:

- “이 인물은 이전 장면에서 이 사실을 아직 모릅니다.”
- “이 플롯 스레드는 오랫동안 다시 등장하지 않았습니다.”
- “최근 문단에서 비슷한 종결 표현이 반복됩니다.”

확신이 낮으면 아무것도 보여 주지 않는 것이 올바른 결과일 수 있습니다.

### Ask MINT

Ask MINT는 영구적인 챗봇 사이드바가 아니라 **프로젝트 문맥에 잠깐 접근하는 도구**를 지향합니다.

`⌘K`에서 현재 프로젝트 전체를 대상으로 질문하고, 결과가 원고의 사실을 주장한다면 가능한 한 실제 문서 근거로 돌아갈 수 있어야 합니다.

---

## Story memory

소설을 이해할 때 하나의 거대한 요약문에 모든 것을 넣지 않습니다.

```text
Work
└─ Part / Arc
   └─ Chapter
      └─ Scene
         └─ Atomic Story Knowledge
```

Atomic knowledge의 예:

- Event
- Fact
- Character State
- Character Knowledge
- Relationship State
- Object State
- Story Thread

요약은 **진실의 원천이 아니라 retrieval router**입니다.

사용자에게 보여 주는 중요한 판단은 최종적으로 원고의 실제 evidence까지 내려갈 수 있어야 합니다.

Fiction의 시간도 한 축으로 단순화하지 않습니다.

- **discourse position** — 원고에 등장한 순서
- **story time** — 작품 세계에서 실제로 일어난 순서

시간을 알 수 없다면 모른다고 유지합니다. AI가 빈칸을 상상해서 강한 모순 경고를 만들어서는 안 됩니다.

---

## Your manuscript is yours

MINT의 데이터 우선순위는 다음과 같습니다.

```text
User Canon
> explicit manuscript text
> deterministic inference
> agent inference
> summary
```

사용자가 직접 고친 인물 설정, 관계, 사건 판단, 의도된 모순 같은 결정은 재분석이 덮어쓰지 못해야 합니다.

반대로 AI가 만든 요약·추출·검색 인덱스는 다시 만들 수 있어야 합니다.

0.2.0의 프로젝트 저장 목표:

```text
~/Documents/MINT/Projects/<project-id>/
├─ project.json
├─ Documents/
├─ Notes/
├─ Assets/
└─ Intelligence/
```

기존 `entries.json`에서 프로젝트 구조로 이동할 때도 **원본을 제자리에서 변형하지 않는 비파괴 migration**을 원칙으로 합니다.

---

## Current state — MINT 0.2.0

0.2.0은 현재 개발 중입니다. README는 목표와 현재 구현을 구분합니다.

### Landed on `main`

- ✅ generic `WritingProject` / `WritingDocument` domain
- ✅ `ProjectStore` + non-destructive legacy migration foundation
- ✅ project-scoped `ProjectSession`
- ✅ Fiction `Write / Map / Review` vs General `Write / Outline / Review` routing
- ✅ per-project workspace mode persistence
- ✅ document-centric workspace shell baseline
- ✅ Navigator drag-collapse / persistent tool docking / titlebar geometry
- ✅ Ghost Completion wrapped-line geometry regression coverage
- ✅ project-first onboarding core
- ✅ cancellable provider-independent Writing Quality core
- ✅ native editor, Ghost Completion, search/export and existing Fiction intelligence foundations

### Still in progress

- 🚧 First-run UI + project-first runtime handoff
- 🚧 Living Margin
- 🚧 hierarchical story memory
- 🚧 atomic / temporal Story Knowledge
- 🚧 structure-first retrieval
- 🚧 evidence-bounded continuity judge
- 🚧 durable User Canon integration
- 🚧 Ask MINT
- 🚧 Story Map
- 🚧 Review presentation
- 🚧 Story Context → Ghost
- 🚧 General Writing end-to-end proof
- 🚧 Korean morphology provider / writing-quality rules
- 🚧 final release-readiness and large-document performance evidence

> **Important:** the current primary editor flow still contains the legacy `EntryStore` compatibility path while #118 completes the project-first runtime handoff.  
> Therefore some 0.2.0 workspace UI can be present in code but not yet appear in the normal legacy document flow. Replacement surfaces land before legacy primary UI is retired.

The release contract and live dependency map are tracked in [Epic #99 — MINT 0.2.0: Writing Platform, Fiction First](https://github.com/sorbetsharkroundhand/MINT/issues/99).

---

## Technology

| Area | Stack |
| --- | --- |
| Language | Swift 6 |
| Platform | macOS 14+, Apple Silicon |
| UI | SwiftUI + AppKit / TextKit |
| Local inference | Apple MLX |
| Package manager | Swift Package Manager |
| Model runtime | mlx-swift, mlx-swift-lm |
| Tokenization / Hub | swift-transformers, swift-huggingface |
| Math rendering | SwiftMath |
| Tests | XCTest + app/UI smoke |

MINT deliberately keeps the editor and domain model independent from any single model provider or Fiction-specific type where that coupling is not required.

---

## Run from source

### Requirements

- Apple Silicon Mac
- macOS 14+
- Xcode 16+
- Swift 6 toolchain

### Development run

SwiftPM can build the Swift executable, but MLX also needs its Metal shader library.

```bash
git clone https://github.com/sorbetsharkroundhand/MINT.git
cd MINT

scripts/prepare-metallib.sh
swift run MINT
```

`prepare-metallib.sh` can reuse its cache and rebuilds the metallib when the pinned `mlx-swift` revision changes.

### Build a local `.app`

For a path closer to the app lifecycle tested in CI:

```bash
scripts/build-mint-app.sh
open build/MINT.app
```

The build script prepares `mlx.metallib`, builds the release executable, creates `build/MINT.app`, and applies an ad-hoc signature for local execution.

### Verification

```bash
swift test
swift build
swift build --product MINTBench

scripts/build-mint-app.sh
scripts/smoke-mint-app.sh
scripts/ui-smoke-mint-app.sh
```

---

## Repository map

```text
Sources/
├─ MINT/              thin @main application shell
├─ MINTCore/
│  ├─ Project/        WritingProject, ProjectStore, ProjectSession
│  ├─ Workspace/      shell, routing, navigator/workspace presentation
│  ├─ Editor/         TextKit editor and Ghost Completion
│  ├─ Inference/      MLX runtime, completion, context assembly
│  ├─ Knowledge/      story understanding / retrieval foundations
│  ├─ Fiction/        Fiction-specific domain intelligence
│  ├─ Storage/
│  └─ Export/
└─ MINTBench/         quality / latency benchmark CLI

Tests/
└─ MINTCoreTests/
```

Canonical architecture and implementation planning live in:

- [PLAN.md](PLAN.md)
- [MINT 0.2.0 Design Specification](docs/superpowers/specs/2026-09-02-mint-0.2.0-design.md)
- [Epic #99](https://github.com/sorbetsharkroundhand/MINT/issues/99)

---

## The direction

MINT가 잘 만들어졌을 때 사용자는 “AI 기능을 쓰고 있다”고 계속 의식하지 않아야 합니다.

그저 글을 쓰고,

- MINT는 작품을 뒤에서 읽고,
- 중요한 맥락을 기억하고,
- 필요할 때만 조용히 알려 주고,
- 물어보면 프로젝트 전체에서 근거를 찾아오고,
- 사용자가 내린 결정을 기억하며,
- 절대로 작가보다 작품을 더 잘 안다고 행동하지 않습니다.

**The writer owns the story. MINT helps them keep hold of it.**
