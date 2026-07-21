# KeyScene 도메인 — 작가 중심 핵심 장면 & 챕터 단위 분석 (설계)

> **상태: P0-A 구현 완료 · P0-B 측정 구현 대기.** 2026-07-21 기준.
> 철학은 [CLAUDE.md](../CLAUDE.md), 시스템 설계·로드맵은 [PLAN.md](../PLAN.md).
> 선행 조사: [docs/m6-scene-split.md](m6-scene-split.md) · [docs/m6-events.md](m6-events.md).

## 0. 배경 — Scene = Chunk 혼동의 재규정

현재 `DocumentOutline.Scene`(DocumentOutline.swift:22)은 **서사적 Scene이 아니라
800~1500 UTF-16 CDC 분석 청크**다. 한 타입이 세 역할을 겸한다:

1. LLM 입력 상한을 지키는 기술 청크 (`segmentRanges`·`sentencePieces`·`fnv1a`)
2. 캐시 무효화·메모 키 (`contentHash`)
3. 사용자·Agent 노출 단위 (`get_outline`·`read_scene`·`NarrativeView`)

그 결과 헤딩 7개인 「개츠비」가 **~87개 "씬"** 으로 노출된다 (PLAN §16-3). CDC 자체는
원문 100% 분석·증분·편집 국소화에 필요하지만, **그 결과를 서사 단위로 노출하는
결합**이 문제다.

MINT가 작가에게 보여줄 것은 **원문을 빠짐없이 덮는 Scene 목록이 아니다.** 작가가
관리할 가치가 있다고 판단하거나 AI가 제안한 **선택적 핵심 사건(sparse)** 이다.
원문 전체를 다시 `NarrativeScene`으로 분할하는 projection도 만들지 않는다 — 그것도
"모든 텍스트가 어떤 Scene에 속해야 한다"는 틀린 가정을 유지한다.

### 이미 존재하는 것 (신축 금지 — 재사용)

요구 모델의 대부분은 이미 코드에 있다:

| 요구 개념 | 기존 실체 (파일:라인) |
|---|---|
| 중요도·참여·근거 인용 | `StoryEvent.importance/participants/quote` (EventLog.swift:11) |
| before/after 상태 | `StateDelta` + `stateAt` fold (EventLog.swift:53, KnowledgeStore.swift:688) |
| 인과(causalParents/setupFor/payoffOf) | `CausalLink` 6종 (KnowledgeStore.swift:946·951) |
| 병합 | `.eventIdentity` 오버라이드 (Narrative.swift:331) |
| 작가의 중요도·요약 수정 | `.eventImportance`·`.eventSummary` (Narrative.swift:299·301) |
| 플롯 아크(setup/payoff) | `PlotThread` (PlotThread.swift) |
| 작가 결정이 재분석을 이김 | `NarrativeOverride`·`RecordedConversation` in `entries.json` |

**진짜 빠진 4가지:** ⓐ 작가가 **직접 저작**하는 sparse 사건(추출 편집이 아닌 저작),
ⓑ `sourceRange == nil` **계획 단계** 사건, ⓒ `planned/drafted/confirmed` 상태와
`authorConfirmed` 보호, ⓓ **안정 UUID**(현 `StoryEvent.stableKey`는 요약 해시라
요약 편집 시 바뀜, EventLog.swift:45).

> **이름 충돌 (반드시 준수):** `StoryEvent`는 이미 Narrative Graph 전체의 기반
> 타입이다. 재사용하면 그래프가 깨진다. 새 타입은 **`KeyScene`**(UI "핵심 장면").
> 기존 `StoryEvent`는 P0에서 **rename하지 않는다** — 전역 rename은 회귀 통과 후
> 별도 정리 단계.

## 1. 도메인 모델

### 1.1 AnalysisChunk (내부 기술 단위 — 노출 금지)

- 기존 `DocumentOutline.Scene`을 **그대로** 내부 청크로 취급한다. P0에서
  `public typealias AnalysisChunk = DocumentOutline.Scene`만 도입하고 로직·필드는
  건드리지 않는다 (전역 rename 금지).
- 책임: LLM 입력·검색·색인·캐시 무효화. 원문 전체를 빈틈없이 타일링. 길이/토큰
  상한으로 여러 개 생성. **LLM 0회로 결정적 생성** (이미 그러함 —
  `DocumentOutline.parse`).
- 사용자에게 Scene으로 노출하지 않는다 (P0-A가 노출 경로를 끊는다).

### 1.2 KeyScene (작가 큐레이션 — entries.json)

원문을 덮지 않는 sparse annotation. `RecordedConversation`과 같은 자리(entries.json)
에 산다 — 재분석이 못 지운다.

```swift
struct KeyScene: Codable, Equatable, Sendable, Identifiable {
    let id: UUID                    // 안정 정체성 (내용 해시 아님)
    var chapterAnchor: [String]     // 헤딩 경로 — 계획 사건(range=nil)의 소속
    var title: String
    var summary: String
    var sourceRange: Range<Int>?    // nil = 계획 단계 (아직 안 써짐)
    var anchorSnippet: String?      // 재앵커용 원문 조각(≤40자)
    var status: Status              // planned | drafted | confirmed
    var importance: Int             // 1–5 (작가 최종 판단)
    var characters: [UUID]          // 등록 카드 참조
    var povCharacter: UUID?
    var linkedEventKeys: [String]   // 기존 StoryEvent.stableKey 참조 — 인과·상태 재사용
    var authorConfirmed: Bool       // true면 재분석이 못 지운다
    var createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable, Sendable { case planned, drafted, confirmed }
}
```

**단순화 결정:** 요구 모델의 `goal/conflict/turningPoint/outcome/before/after`는
`StateDelta`·`CausalLink`와 중복이다. P0에선 **필수 컬럼으로 만들지 않는다** —
`linkedEventKeys`로 기존 기계를 참조하고, craft 필드는 선택적 주석(P1 LLM/작가가
채움)으로 남긴다. Chapter는 별도 엔티티를 만들지 않고 `chapterAnchor`(헤딩 경로)로
파생한다 — **Chapter는 KeyScene 0개 가능**(빈 것이 정상, 오류 아님).

### 1.3 StoryEventCandidate (비영속 제안)

```swift
struct StoryEventCandidate: Sendable, Equatable {
    let ephemeralID: String
    var proposedRange: Range<Int>?
    var proposedTitle: String
    var proposedSummary: String
    var evidence: [String]          // 원문 인용(검증됨)
    var importanceSignals: [String] // "인과 3개","되돌릴 수 없는 결정","비밀 공개"…
    var confidence: Double
    var inputHash: String           // (청크 해시 + 규칙/후보 버전) — 재제안 금지
}
```

저장하지 않는다. 스냅샷 파생 시 규칙으로 재생성, `inputHash`로 메모. 작가가
후보를 **등록/무시/병합/범위수정** 하면 KeyScene이 된다.

### 관계

- KeyScene 1 : N AnalysisChunk (하나의 KeyScene이 여러 청크에 걸칠 수 있음).
- Chapter(헤딩 그룹) 1 : 0..N KeyScene.
- KeyScene → `linkedEventKeys` → 기존 StoryEvent/CanonicalEvent (인과·상태·플롯 재사용).
- StoryEventCandidate → (작가 확정) → KeyScene.

## 2. P0-A — KeyScene 저장·수동 관리·UI/Agent 노출 수정

작가가 **모델 없이도** 핵심 장면을 관리할 수 있는 큐레이션 레이어. 순수 additive.

### 2.1 저장 (하위 호환)

- `JournalEntry.keyScenes: [KeyScene]?` 신규 옵션 키 (레거시 파일 nil).
  `recordedConversations`(EntryStore.swift:91)와 **동일 패턴**. schemaVersion 불변.
- `EntryStore`에 `upsertKeyScene`/`removeKeyScene`/`confirmKeyScene` 추가
  (`recordConversation`/`removeRecordedConversation`, EntryStore.swift:836·848 패턴).
  변경 시 `narrativeOverridesDidChange`로 rehydrate.

### 2.2 스냅샷 파생 + 재앵커

- `KnowledgeSnapshot`에 `keyScenes: [KeyScene]` 파생 배열 추가 (작가 오버레이가
  AI 후보를 이김). 계획형(`sourceRange == nil`)도 실린다.
- **sourceRange reconcile:** 원문 수정 시 `anchorSnippet` + 범위 중첩으로 위치를
  되찾는다 (`NarrativeOverrides.rekeyedForScenes`, Narrative.swift:408 +
  `ConversationDetector.reanchor` 사다리 재사용). 실패분은 **stale 보존·표시**
  (조용한 삭제 금지). **id는 절대 바뀌지 않는다.**
- `authorConfirmed == true`인 KeyScene은 재분석이 지우거나 덮지 못한다.

### 2.3 UI (작가 흐름)

- 사이드바 "핵심 장면" 섹션 (기존 바이블/서사/컨텍스트 섹션 옆). 목록 = KeyScene
  담화 순서 + 계획형 별도 그룹.
- **발견형:** 인덱서가 idle에 후보를 제시(비침습) → 작가가 등록/무시/병합/수정.
- **계획형:** 빈 상태에서 "핵심 장면 추가"(`sourceRange == nil`, `.planned`).
  그 대목을 나중에 쓰면 앵커 매칭으로 `.drafted` 승격 제안.
- **혼합형:** 계획 KeyScene ↔ 발견 후보를 범위 중첩/`linkedEventKeys`로 연결.
- 기존 `NarrativeView` 사건 상세(중요도·병합 편집)는 KeyScene 승격 진입점이 된다.

### 2.4 Agent/UI 노출 차단

- `get_outline`(WritingTools.swift:229)이 청크 대신 **KeyScene("핵심 장면")** 을
  반환. 청크 `contentHash`·`(분할 N)` 라벨(WritingTools.swift:638) **은닉**.
- `read_scene`은 KeyScene 대상 + `offset`/`limit` 페이지 조회. 청크 원문 직접 읽기는
  내부 도구로만(모델·UI에 청크 번호 미노출).
- `NarrativeView`의 `(N/M)`·`truncated` 청크 노출 축소.

## 3. P0-B — 청크별 LLM 호출 → 챕터 단위 분석 축소

현재 `runPass`(BackgroundIndexer.swift:465)는 청크마다 요약·사건·앎·구간 4개 루프를
돈다 (개츠비 첫 분석 ≈ 청크 87 × 4 ≈ **~348회** + 그래프/플롯). 이를 **변경된
Chapter 단위**로 묶는다.

### 3.1 Dirty 단위 = Chapter

- Chapter = 헤딩 경로 `prefix(2)` 그룹 (기존 `propagate`, BackgroundIndexer.swift:744).
- 챕터 결합 해시 = 소속 청크 `contentHash`들의 `combinedHash`(이미 있음). 이 해시가
  바뀐 챕터만 재분석 — **챕터 단위 증분.** 미변경 챕터는 건너뛴다(전체 재분석은
  복구 수단, CLAUDE.md §2-3).

### 3.2 규칙 → 제한 LLM → 작가 확정 파이프라인

1. **후보 생성(결정적, LLM 0회):** 변경된 챕터의 청크에서 `StoryEventCandidate`를
   규칙으로 뽑는다. 신호는 이미 있는 것들: `importance ≥ 4` 사건, `StateDelta`
   존재(목표·관계·생사 변화), `CausalLink` 끝점, 명시적 장면 구분자
   (`isSceneBreakLine`), 대화 밀도(`Conversation.index`). **임베딩·LLM 불요.**
2. **제한 LLM 검토(챕터당 ≤ 1회):** 후보가 있을 때만, LLM에 **후보 digest**(요약 +
   짧은 근거 인용, 원문 아님)를 주어 구조화 JSON으로 확정/순위/병합을 받는다.
   digest라 프리필 예산(≤1500 토큰) 안 — "타이핑 재개 → 예측 대기" 최악 지연
   불변(BackgroundIndexer.swift:63). 결과는 확정 KeyScene이 아니라 **후보 보강**.
3. **메모:** 키 = `(챕터 해시, 후보 집합 해시, 스키마 버전)`. 같은 입력·후보엔
   재호출 없음. 후보 없으면 호출 없음.
4. **작가 확정:** 최종 판단자는 작가 (P0-A UI). AI는 제안만.

### 3.3 요약 피라미드 재편

- **청크별 요약 개별 호출 제거.** B 블록의 요약 출처를 청크
  (`summariesByHash[chunkHash]`)에서 **작품 요약 + 챕터 요약 + 인접 KeyScene 요약**
  으로 옮긴다. 근거: 근거리 맥락은 이미 C 창(원문)에 있고, 원거리는 챕터 요약이면
  충분 — 청크 요약 층은 대체로 잉여다.
- 챕터 요약 = 변경 챕터당 1회 rollup(기존 `rollup`, BackgroundIndexer.swift:1109
  재사용). 작품 요약 = 챕터 요약에서.

### 3.4 핵심 결정 & 위험 — Narrative Graph 입력 전환

⚠️ **가장 큰 결합점.** `canonicalEvents`·`causalLinks`·`plotThreads`(M8/M9)는
**청크별 `StoryEvent` 추출**을 입력으로 한다. 청크별 추출을 없애면 그래프 입력이
사라진다. 두 경로:

- **(A) 단계적(권장):** P0-B는 먼저 **챕터 게이팅 + 후보 통합**만 한다 — 사건·앎·
  구간 추출을 청크별에서 **변경 챕터 단위 묶음 호출**로 통합하되, 산출 타입
  (`StoryEvent` 등)은 유지해 그래프가 그대로 돈다. 이것만으로 **첫 분석 호출 수가
  청크 수 → 챕터 수 규모로** 준다. KeyScene은 이 사건들 위에 큐레이션 레이어로 얹힌다.
- **(B) 전면:** 그래프 노드를 청크 `StoryEvent` → KeyScene으로 교체. 사건 모델이
  sparse·작가 큐레이션과 완전히 정렬되지만 M8/M9 재작성 — **P1 이후.**

**P0-B = 경로 (A).** 경로 (B)는 열린 결정(§9)으로 남긴다.

### 3.5 예상 감소량 (측정 대상)

- 개츠비 첫 분석: 청크 87 × 4 ≈ ~348 → 변경 챕터 7 × (후보검토 1 + 사건묶음 1 +
  요약 1) ≈ **~21회** (약 **94% 감소**, 경로 A 기준).
- ⚠️ CLAUDE.md §2-7(측정 없이 튜닝 없음): **MINTBench로 호출 수 감소와 예측 품질
  무회귀를 측정**해야 완료. B 블록 요약 출처 변경은 리플레이 벤치의 acceptance
  기준(수락 프록시 무회귀)에 건다.

## 4. P1 — 임베딩 후보 탐색 · Top-K context · Agent context 개선

P0(KeyScene 모델 + 챕터 분석 + 회귀 테스트)가 끝난 뒤에만 착수.

- **임베딩 후보 탐색:** `MLXEmbedders`(mlx-swift-lm)는 현재 `Package.swift`에 **없다**
  — 추가 = 새 의존성 + 새 모델. `intfloat/multilingual-e5-small` **spike**로
  한국어 품질·메모리·다운로드 크기·배치 속도 먼저 검증. 용도: 인접 블록 의미 변화
  감지 · 후보 범위 생성 · 관련성 검색 · 후보 중복/병합 보조. **유사도만으로 중요도
  확정 금지** — "변화/관련" 신호일 뿐.
- **Top-K context retrieval:** Agent에 전체 outline·전체 청크를 한 번에 주지 않는다.
  현재 위치 주변 원문 + 최근접 확정 KeyScene + 이전/다음 핵심 사건 요약 + 현재
  Chapter 목적 + 인과 연결 KeyScene + 필요한 청크만 Top-K. `read_scene`(1500자 청크
  하나씩) 인터페이스 재검토.
- **NLTokenizer + 모델 토크나이저 청킹:** char-CDC를 문장 경계(`NLTokenizer`) +
  실제 토큰 수 기반 목표-토큰 묶음으로 개선(품질, 이미 0-LLM). CDC는 증분 무효화용
  유지 가능.
- **AgentBootstrapContext 주입** + 도구 통합(`get_story_overview`·`get_scene`·
  `search_story`·`get_timeline`·`get_context_at_cursor`).
- **전역 rename** `Scene → AnalysisChunk` (회귀 통과 후 정리).

## 5. 하위 호환 전략

- **schemaVersion 유지(7).** 사이드카 폐기·재구축 **없음.** KeyScene은 사이드카가
  아니라 entries.json.
- entries.json에 **새 옵션 키만 추가**(`keyScenes`), 레거시 nil fallback. 기존
  override·record·청크 요약 **보존.**
- 사용자 override **일회성 재작성 금지.** 청크 요약·분석 캐시 최대한 유지.
- 전역 rename 금지 — 별칭(`AnalysisChunk`)만. 실제 rename은 P1.
- **모델 없이 동작:** KeyScene CRUD·후보 규칙은 순수 결정적 — 모델 미로드 시에도
  편집·수동 관리 동작.

## 6. 테스트 · Acceptance Criteria

**결정적 단위 테스트 (모델·Metal 없음):**
- KeyScene CRUD 왕복(entries.json) · 레거시(키 없는) 파일 로드
- 앞부분 텍스트 삽입 후 KeyScene `id` 불변
- sourceRange reconcile(범위 중첩·앵커) 성공/stale
- 계획형(`sourceRange == nil`) 저장·로드·승격
- 규칙 후보가 같은 입력에 재제안 안 함(`inputHash` 메모)
- `get_outline`이 청크 해시·`분할 N` 미노출
- 챕터 dirty 게이팅: 미변경 챕터 재분석 안 함 (호출 수 assert)
- `authorConfirmed` KeyScene이 재분석 후 생존
- 모델 없이 CRUD 동작

**Acceptance criteria:**
- ✅ 글자 수 늘어도 핵심 장면 수 자동 증가 안 함 (sparse, 작가 등록분만)
- ✅ Chapter는 핵심 장면 0개 가능 (파생, 빈 것이 정상)
- ✅ AnalysisChunk 생성 LLM 0회
- ✅ AnalysisChunk가 UI에서 Scene으로 노출 안 됨
- ✅ LLM은 청크별이 아니라 **후보 있는 Chapter 단위**로 제한 (P0-B, MINTBench로 측정)
- ✅ 작가 확정 KeyScene이 재분석으로 안 사라짐 (`authorConfirmed`)
- ✅ 앞부분 삽입으로 기존 KeyScene id 안 바뀜 (안정 UUID)
- ✅ 기존 override·캐시 보존 (schemaVersion 유지)
- ✅ 모델 없어도 편집·수동 KeyScene 관리 동작
- ✅ (P0-B) MINTBench: 첫 분석 LLM 호출 수 유의미 감소 + 리플레이 수락 프록시 무회귀

## 7. 파일별 변경 (P0)

| 파일 | 변경 이유 |
|---|---|
| `Knowledge/KeyScene.swift` (신규) | `KeyScene`·`StoryEventCandidate`·규칙 `KeySceneCandidateDetector`(결정적) |
| `Storage/EntryStore.swift` | `JournalEntry.keyScenes` + `upsertKeyScene`/`removeKeyScene`/`confirmKeyScene` |
| `Knowledge/KnowledgeStore.swift` | 스냅샷 `keyScenes` 파생 + reconcile + stale + 후보 파생 |
| `Knowledge/BackgroundIndexer.swift` | 챕터 dirty 게이팅 + 후보 통합 검토(≤1회/챕터) + 청크별 루프 통합 (경로 A) |
| `Knowledge/DocumentOutline.swift` | `AnalysisChunk` 별칭 + "청크는 내부 단위" 주석 (parse 무변경) |
| `Agent/WritingTools.swift` | `get_outline`→KeyScene, `read_scene` 페이지, 청크 라벨 은닉 |
| `NarrativeView.swift` | "핵심 장면"(KeyScene) 표시·CRUD 패널, 청크 `(N/M)` 노출 축소 |
| `Sources/MINTBench/main.swift` | 챕터 분석 LLM 호출 수 측정 축 (§3.5) |
| `Tests/MINTCoreTests/KeySceneTests.swift` (신규) | §6 결정적 테스트 |

### P0-A 구현 기록 (2026-07-21)

- `KeyScene` 저장과 작가 CRUD/확정/병합, 안정 UUID, 계획형 범위 nil을 구현했다.
- `anchorSnippet` 재앵커 실패는 `staleKeySceneIDs`로 보존하며 사용자 데이터를
  자동 삭제하지 않는다. 스냅샷 재조립만 수행하므로 모델 없이 동작한다.
- `get_outline`/`read_scene`은 KeyScene UUID만 사용하고 페이지 조회한다. CDC 해시와
  `(분할 N)`은 반환하지 않는다. NarrativeView도 같은 헤딩의 CDC 후속 청크 표지를
  숨기고 별도 핵심 장면 패널에서 등록·수정·확정·병합·삭제를 제공한다.
- `ContextAssembler`는 커서 이전 KeyScene을 우선하고 겹치는 청크 요약을 제외한다.
- P0-B의 호출 경로 변경은 MINTBench 호출 수/수락 프록시 측정과 함께 수행해야 한다.
  현재 청크별 추출 호출은 유지된다(측정 없이 품질 경로를 바꾸지 않는 §2-7 준수).

## 8. 위험 · 롤백

| 위험 | 완화 | 롤백 |
|---|---|---|
| KeyScene reconcile 실패로 위치 유실 | stale 보존·표시, id 불변, 유닛테스트 | entries.json 불변 — 원문 복원 시 재앵커 |
| B 블록 요약 출처 변경이 예측 품질 저하 | MINTBench acceptance 기준, 경로 A 유지 | 청크 요약 경로 복구(플래그) |
| Narrative Graph 입력 전환(경로 A) 회귀 | 산출 타입 유지, 그래프 무변경 | 챕터 통합 끄면 청크별 복귀 |
| 챕터가 프리필 예산 초과 | LLM은 후보 digest만(원문 아님) | — |
| 새 의존성 리스크 | P0는 임베딩 없음(규칙만) | — |

전체 롤백 = 파생 캐시(사이드카)는 삭제로 원문 무손상 복구. entries.json의 KeyScene은
사용자 데이터라 보존.

## 9. 열린 결정

1. Narrative Graph 노드를 청크 `StoryEvent` → KeyScene으로 **전면 교체(경로 B)** 할지 —
   P0는 경로 A, 전면 교체는 P1 이후 (M8/M9 재작성 규모).
2. KeyScene UI 노출 수위 — 기본 접힘 + 요청 시 상세(바이블 노출 수위 §16-6와 동일 논지).
3. 계획형 KeyScene의 챕터 앵커가 헤딩 재편에서 흔들릴 때의 재앵커 정책.
4. P0-B 챕터 통합 호출의 최적 digest 형식·토큰 예산 — MINTBench로 확정.
