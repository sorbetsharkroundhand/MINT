# MINT → Agentic Writing Environment: 경쟁사 조사 및 재설계 보고서

> MINT를 **"OpenCode for Writing"** — 온디바이스 Writing Agent Environment — 로
> 재정의하기 위한 조사·설계 보고서. 핵심 Agent 모델은 Qwen3.6 계열(MLX 온디바이스).
> 철학·불변 규칙은 [CLAUDE.md](../CLAUDE.md), 시스템 설계·로드맵은 [PLAN.md](../PLAN.md).
> 이 문서는 **조사·설계**다 — 구현 지시가 아니다. 실제 착수는 §17 Migration Plan 참조.

추측과 코드에서 확인한 사실을 구분해 표기한다: **[코드확인]** / **[추론]** / **[미확인]**.
경쟁사 주장은 CONFIRMED/INFERRED/UNKNOWN + 출처 URL(§3).

> 조사 범위: 코드베이스 실제 정독(§2, §7~§19) + 경쟁사 3사 심층 웹 리서치
> (Sudowrite·NovelCrafter·NovelAI) + 기타(DreamGen·Squibler·Subtxt·AI Dungeon) +
> Coding Agent(OpenCode·Aider·Cline·Claude Code) 아키텍처(§3, §9.5).

**설계 결정(확정)**: ① **Agent ↔ 자동완성 공존**(같은 Story Intelligence 공유,
자동완성 대체 아님, ADR-4). ② **MVP = 읽기 전용 Agent 먼저**(조회·조언, 편집은 P1).
③ 이 문서를 저장소 설계 자산으로 유지(PLAN §14 M10 포인터).

---

## 1. Executive Summary

- MINT는 이미 "예측이 작품을 이해하는" **Story Intelligence 자산**을 매우 깊이
  갖췄다 — 인물·사건·상태 델타·앎·관계·서사 구간·정본 사건·인과·시간순·플롯
  스레드까지. 결정적으로, 이 지식은 **`KnowledgeSnapshot`의 순수 질의 메서드**로
  이미 노출돼 있고(`stateAt`, `honorific(from:to:before:)`, `events(before:)`,
  `causes/effects`, `expectedSpeaker`, `position(at:)` 등 ~25종), 백그라운드
  추출 로직도 **`nonisolated public static` 순수 함수**(`analyzeScene`,
  `extractEvents`, `analyzeEventGraph`, `analyzePlotThreads` …)로 이미 분리돼 있다.
- 따라서 재설계의 본질은 **새로 만드는 것이 아니라 승격**이다: 기존 질의·추출·검색·
  편집 인프라를 **Tool Registry**로 감싸고, 그 위에 **Qwen3.6 Agent Loop**를 얹는다.
  자동완성과 Agent가 **동일한 Story Intelligence를 공유**한다.
- 기술 검증: **네이티브 tool calling 가능** — mlx-swift-lm 3.31.3 `UserInput(chat:tools:)`
  + Qwen3.6 Hermes 챗 템플릿 + `generate` 스트림의 `.toolCall`. 리스크는 "가용성"이
  아니라 공격적 양자화(2bit/A3B) 하의 "형식 신뢰도"다 → lenient-parse/strict-validate
  래퍼 + 폴백 프로토콜로 대응 (기존 EventParser 철학과 동일).
- 온디바이스 제약을 전제로: Agent는 원고 전체를 context에 넣지 않는다. **Tool로
  검색·조회**하고, Context Budget/Compression으로 세션을 관리한다.
- **경쟁 포지셔닝**: 조사 결과 **어떤 경쟁사도 진짜 tool-calling Agent가 없다**
  (Sudowrite Chat "Allow edits"의 승인형 multi-step 편집이 가장 근접). 반대로
  MINT는 Story Intelligence 깊이에서 이미 앞선다(자동 인물 감지·상태 시간축·존대
  매트릭스·인과/플롯 그래프·일관성 검사 — 경쟁사 대부분 부재). 경쟁사의 컨텍스트
  조립(NovelAI 예약/우선순위, NovelCrafter 6단계 Codex, Sudowrite Saliency+Chapter
  Continuity)은 전부 MINT ContextAssembler가 **더 똑똑한 축(엔티티·상태·시점 차단)**
  으로 이미 수행. → MINT의 승리 조합 = **깊은 Story Intelligence + 진짜 Agent + 완전 로컬**.

---

## 2. 현재 MINT 아키텍처 분석 [코드확인]

### 2.0 세 평면 (PLAN §4)
- **문서 평면(유일한 진실)**: `EntryStore`(entries.json) · `BlockTextView`(에디터) ·
  `DocumentOutline`(헤딩→씬 파서).
- **지식 평면(재구축 가능 파생 캐시)**: `BackgroundIndexer`(유휴 파이프라인) ·
  `KnowledgeStore`(사이드카 + `KnowledgeSnapshot` 질의).
- **추론 평면**: `CompletionController`(게이트·디바운스) · `ContextAssembler`(A/B/C 조립) ·
  `CompletionEngine`(MLX 단일 모델 actor).

### 2.1 기능별 분석 (현재/담당/입력/출력/재사용성/Tool화/구조 문제)

**에디터 (`Editor/BlockTextView.swift`, 3765행)**
1. 무엇: TextKit1 블록 에디터, 인라인 마크다운, 고스트 렌더(Tab/→/Esc), IME 조합
   게이트, 자체 캐럿, 이미지 오버레이, 증분 직렬화, 문서 내 찾기(⌘F).
2. 담당: `BlockTextView` + `Coordinator`, `InlineStyle`, `ParagraphSplitter`, `TextStats`.
3. 입력: 키 이벤트, 저장 본문(markdown). 4. 출력: 편집 이벤트, prefix/caret, `suggestionDidChange`.
5. 재사용: 편집 적용 지점(삽입/치환)은 Agent Patch의 실행 지점으로 재사용 가능.
6. Tool화: 직접 X(뷰). 단 "selection 조회/치환/삽입"의 **실행 백엔드**로 쓰인다.
7. 구조 문제: 3천 행 모놀리스(PLAN §16). 지식 로직 반입 금지 규율은 지켜짐.

**문서/프로젝트/챕터 관리 (`Storage/EntryStore.swift`, 966행)**
1. 무엇: 다중 저널 + 폴더 트리(중첩), 활성 문서, 디바운스 autosave, 전역 검색,
   문서 종류(저널/소설) 전환, AI 폴더 명명.
2. 담당: `EntryStore`(@MainActor), `JournalEntry`, `JournalFolder`, `CharacterCard`.
3. 입력: 본문 편집, 구조 변경. 4. 출력: entries.json, `documentDidChange` 훅, `search()` 결과.
5. 재사용: **프로젝트 구조·문서 목록·검색·현재 문서 조회의 소스** — Tool 다수의 백엔드.
6. Tool화: `list_documents` / `get_active_document` / `search_text`(=`EntryStore.search`) /
   `read_document`가 여기서 나온다.
7. 구조 문제: 1작품=1 `JournalEntry`(body 전체가 markdown). "챕터"는 **별도 엔티티가
   아니라** 헤딩에서 파생(`DocumentOutline`). 전 원고가 entries.json 단일 파일(PLAN §16
   스케일 부채). "폴더=작품"은 열린 질문.

**자동완성 (`Editor/CompletionController.swift` 555 + `Inference/*`)**
1. 무엇: 게이트(마스터→IME 조합→문단 끝→길이→디바운스) → 모드 선택(fast/smart/story
   [-dialogue]) → 조립 → 단일 생성 → 고스트. 대화 기록 인라인 제안도 여기.
2. 담당: `CompletionController`(MainActor), `ContextAssembler`, `CompletionEngine`,
   `PromptCache`.
3. 입력: prefix, caret, `DocumentContext`(제목·장르·카드), `KnowledgeSnapshot`.
4. 출력: `suggestion`(고스트), `ContextReport`(인스펙터), `AcceptanceMetrics` 로그.
5. 재사용: **동일 엔진·동일 지식**을 Agent가 공유. Agent 요청은 자동완성을 선점(취소).
6. Tool화: 자동완성 자체는 Tool 아님. 단 "continuation 생성"은 Agent가 부르는
   `continue_writing` tool의 백엔드가 될 수 있다.
7. 구조 문제: 컨트롤러 주변 자동 테스트 부재(PLAN §16).

**MLX 로딩·추론 (`Inference/CompletionEngine.swift`, 514행)**
1. 무엇: `#huggingFaceLoadModelContainer`로 1회 lazy 로드·상주(교체 로드), 취소 가능
   생성, continuation KV 재사용(LCP trim), instruct 챗, `generateOneShot`(백그라운드
   일회성), `generateFolderName`.
2. 담당: `CompletionEngine`(actor), `PromptCache`(`PromptCacheBox`), `ModelDownloadManager`.
3. 입력: `AssembledPrompt`(.continuation/.instruct), `CompletionParameters`(스냅샷).
4. 출력: `Completion`(text + 지연·토큰 지표). 스트림 케이스: `.chunk`/`.info`/`.toolCall`.
5. 재사용: **Agent Loop의 심장** — 여기에 tool-aware 생성 메서드를 추가한다.
6. Tool화: N/A(런타임). 단 `generate(input:cache:parameters:context:)`는 그대로 Agent가 쓴다.
7. 구조 문제: 취소된 생성이 KV 캐시를 버리는 미묘한 버그(PLAN §16). instruct는 KV
   재사용 안 함(챗 템플릿 꼬리 토큰).

**Qwen 호출 구조 / 프롬프트 구성** [코드확인]
- 호출 2형태: (a) **continuation** — 챗 템플릿 없이 조립 텍스트를 그대로 토크나이즈해
  이어쓰기(고스트, KV 재사용). (b) **instruct** — `UserInput(chat:[.system,.user],
  additionalContext:["enable_thinking":false])` → `context.processor.prepare` → 챗 템플릿.
- 예측 프롬프트의 단일 소유자는 `ContextAssembler`. 추출 프롬프트는 `BackgroundIndexer.
  Prompts` enum. 둘 다 **평문 줄 형식 + lenient parse/strict validate**(소형 모델 JSON
  불신). thinking은 항상 off.

**Story Bible / 인물 (`Storage`+`Knowledge/Character*`, `CharacterBibleView`)** [코드확인]
- `CharacterCard`(id·name·aliases·note·locked·autoRegistered) — **사용자 저작이라
  entries.json에 산다**(파생 캐시 아님).
- 감지 깔때기(`CharacterDetector`+`CharacterLexicon`): 형태소기 없이 **유정성 신호**
  (격조사=명사, 여격/호격/발화귀속=사람 필수, 대명사/호칭 제외) → 임계(3+씬·5+언급) →
  신뢰도 3단(HIGH 자동등록/MEDIUM 후보/LOW 제외) + 표기 변형 Entity Resolution(김재형/
  재형/재형이 union-find) + 별칭 병합(사용자 확인). 거부 목록(`rejectedCharacterNames`).
- 등록 후 LLM 프로파일링(`profileCharacter`, 일회성).

**대화 감지·화자 처리 (`Knowledge/DialogueAttribution.swift`, `ConversationCapture.swift`)** [코드확인]
- `Utterance`(화자·청자·존대·텍스트·위치). 귀속: 결정적 2단(인접 서술·교대 규칙),
  모호하면 침묵. 존대: 닫힌 종결어미 규칙. 발화는 **비저장**(패스마다 재계산→스냅샷만).
- 존대 매트릭스: `honorific(from:to:before:)`(방향별 존/반/혼재, 시점 차단 fold).
- 대화 기록: 실시간 결정적 감지(`ConversationDetector`) → 「기록할까요?」 인라인 →
  `RecordedConversation`(entries.json). 깊은 패스가 주제·어조 보완(`analyzeConversation`).

**사건·서사 분석 (`Knowledge/EventLog.swift`, `Narrative.swift`, `NarrativeGraph.swift`,
`PlotThread.swift`, `SegmentAnalysis.swift`)** [코드확인]
- `StoryEvent`(sceneHash 앵커·참여자[등록카드만]·요약≤80·중요도·`StateDelta`들·근거인용).
- `StateDelta`(닫힌 필드: 위치/감정/관계/목표/생사) append-only → `stateAt` fold.
- `SceneInsights`(앎 `KnowledgeDelta`·관계 `RelationDelta` 델타).
- `NarrativeSegment`(씬 내부 시간·관점 층 10종·중첩·복귀·출처·신뢰).
- `CanonicalEvent`+`EventPerspective`(동일 사건 다중 서술 비파괴 묶음, 모순 보존).
- `CausalLink`(6종)·`ChronoOrder`(부분 순서 위상 정렬·Conflict)·`NarrativeFlow`(main/인물/
  시간)·`PlotThread`(branch=플롯, stableID·reconcile·생명주기).

**Narrative View / Git Graph 시각화 (`NarrativeView.swift`, 2049행)** [코드확인]
- 통합 서사 UI: PlotThread 레인 그래프(`ThreadGraphLayout` — 본줄기 슬롯0·Bézier 분화/
  합류) + **흐름(담화순서)/시간순 두 Projection** + 사건 상세 + "검토 필요"(경고·시간
  모순). 소비자일 뿐 — 데이터는 전부 `KnowledgeSnapshot` 질의.
- 구조 문제: 2천 행. 순수 소비자라 Agent tool과 무관하게 유지 가능.

**검색 (`EntryStore.search`, `SearchJump`, ⌘⇧F)** [코드확인]
- 현재: **결정론적 부분 문자열**(제목/본문, 대소문자 무시, 저널 전역). 의미 검색 없음.
- `SearchJump`: 스니펫 질의로 이동(마크다운↔에디터 좌표 불일치 회피). Agent 편집
  결과의 "원문 점프"에 그대로 재사용.
- 구조 문제: 인물·사건·씬 축의 구조화 검색이 없다(엔티티 앵커 검색은 조립기 내부에만).

**저장되는 소설 지식 · 데이터 모델 · 생성/갱신** [코드확인]
- 원문·사용자결정: `entries.json`(`JournalEntry`: body·kind·genre·`characters`·
  `rejectedCharacterNames`·`narrativeOverrides`·`recordedConversations`). **재분석이
  못 덮는다.**
- 파생 캐시: `knowledge/<entryID>.json`(`KnowledgeSidecar` schema v7: sceneSummaries·
  chapter/workSummary·events·insights·segments·eventGraph·plotThreads·conversationMeta).
  스키마 변경 = 폐기·재구축(마이그레이션 코드 금지).
- 예측용: 인메모리 `KnowledgeSnapshot`(값복사, 인덱서가 패스마다 발행 + 웜 하이드레이트).
- 생성: `BackgroundIndexer` 2단 패스(빠른 ~5s: 더티 씬 요약·언급색인·귀속 / 깊은 ~60s·
  비활성: 프로파일·사건·insights·segments·eventGraph·plotThreads·상향 요약). 해시 메모·
  열/전력 게이트·선점·커서 거리순.

### 2.2 현재 AI 기능 의존 관계 (dependency graph) [코드확인]
```
BlockTextView(편집)
  → EntryStore.documentDidChange ─┬→ BackgroundIndexer.noteChange (패스 선점·타이머·웜로드)
                                   └→ (저장)
  → CompletionController.noteEdit (게이트·디바운스)
        pull DocumentContext (EntryStore: 제목·장르·characters)
        pull KnowledgeSnapshot (BackgroundIndexer.snapshot)   ← knowledgeProvider
        → ContextAssembler.assembleWithReport (A/B/C + ContextReport)
        → CompletionEngine.complete (MLX 단일 모델, KV 재사용)
        → suggestion → BlockTextView 고스트
BackgroundIndexer
  → CompletionEngine.generateOneShot (요약·추출·프로파일 — 같은 컨테이너 공유)
  → KnowledgeSidecar (save/load) → makeSnapshot → snapshot 발행
  → CharacterDetector 후보 / ConsistencyChecker 경고 (스냅샷 주기)
KnowledgeSnapshot 질의 ← ContextAssembler(B블록·대화모드) · NarrativeView · CharacterBibleView · ConsistencyChecker
```
- 단일 모델·단일 엔진 공유(이중 로드 금지). 예측이 백그라운드를 선점.
- **핵심 관찰**: 모든 AI 소비자가 이미 `KnowledgeSnapshot` **하나**를 공유한다 →
  Story Intelligence는 이미 단일 소스. Agent는 네 번째 소비자로 자연히 합류한다.

### 2.3 구조적 강점/약점 요약
- 강점: 지식이 이미 질의 API·순수 추출 함수로 노출. 시점 차단(커서 이후 미주입)이
  구조적으로 성립. 오버라이드(사용자 결정) 분리. ContextReport = 이미 만들어진
  "Context Viewer". Pin/Exclude = 이미 만들어진 컨텍스트 제어 오버라이드.
- 약점: 의미 검색·엔티티 축 검색을 외부에서 못 부른다(조립기 내부). 1작품=1문서의
  단일 파일 스케일. 챗/대화형 세션 개념 없음. 편집을 "제안→diff→수락"으로 다루는
  경로 없음(자동완성 고스트만). 3천 행 에디터·2천 행 뷰 모놀리스.

---

## 3. 경쟁사별 상세 기능 조사 (웹 리서치, 출처·신뢰도 표기)

### 3.1 NovelAI (심층) — "keyed lorebook + staged context assembly"
- **모델·컨텍스트** [CONFIRMED]: 자체(Kayra 13B) → Erato(Llama-3 70B 파인튜닝, 8,192) →
  GLM-4.6 "Xialong"(28,672). completion/continuation 루프(챗 아님) + Retry(재롤) +
  Token Probability Viewer(토큰 확률 색상). *교훈: MINT 고스트도 continuation 루프 —
  같은 계보. 토큰 확률 뷰는 MINT ContextReport의 사촌.*
- **Lorebook(핵심)** [CONFIRMED]: 항목 = 제목(AI 비가시)·본문·활성 키·enabled. 활성:
  대소문자 무시 **단어 경계**(`Ai`≠`Aiming`), `/regex/`, `&` AND, Always-On.
  **Search Range = 최근 10,000 문자**(토큰 아님, 뒤에서 앞으로). **Cascading**: 키가
  다른 항목·Memory·A/N까지 검색해 연쇄 활성(범위 제한 무시).
- **Per-entry Context Settings** [CONFIRMED]: Insertion Order(우선순위·먼저 배치·예약)·
  Insertion Position(0=top, 음수=bottom, 단위=token/sentence/newline)·Token Budget(0~1은
  %)·Reserved Tokens(배치 전 예약)·Prefix/Suffix·Trim Direction·Key-Relative 삽입.
- **조립 알고리즘** [CONFIRMED 동작 / 기본 정수값 UNKNOWN]: 예산=ctx−output → 예약 패스
  → Insertion Order 내림차순 배치 → 초과 시 Trim(No-Trim→Newline→Sentence→Token,
  <~30% 남으면 다음 단계/드롭) → 최저 우선순위 드롭. Memory=top(내릴수록 강함),
  Story=하단(최신 강함), A/N=끝에서 ~3 newline(다음 생성에 강한 편향).
- **Context Viewer** [CONFIRMED]: 항목별 Reason(포함/제외 이유)·Key(발동 키)·Reserved·
  Tokens·Trim Type + 소스별 색상 바 + % 표시. *= MINT ContextReport/인스펙터의 상위 버전.*
- **Instruct** [CONFIRMED]: 인라인 `{ 지시 }` 블록(최근 ~1000자에 있으면 자동 활성) —
  rewrite/describe를 "명령"으로. **"Director Tools"는 이미지 기능**(브리프 오류 정정).
- Memory=세계상태 사실(상단), A/N=톤·시점·문체(끝 근처).
- 출처: docs.novelai.net/en/text/{models,editor,lorebook,editor/advancedsettings},
  tapwavezodiac.github.io/novelaiUKB/{Context,Lorebook}.html.

### 3.2 NovelCrafter (심층) — "BYOK + deterministic Codex + prompt DSL"
- **BYOK가 조직 원리** [CONFIRMED]: 자체 모델 없음 — OpenAI/Anthropic/OpenRouter/Groq/
  **Ollama·LM Studio(로컬)** 연결, 토큰 비용은 사용자 몫. *→ 앱의 IP는 모델이 아니라
  컨텍스트 조립·프롬프트 템플릿. MINT는 정반대(완전 로컬 자체 모델) — 대비 축.*
- **Codex** [CONFIRMED]: 6 타입 **Character/Location/Object/Lore/Subplot/Other**
  (⚠️ **Faction은 내장 아님** — Lore/Other/Category로; **Subplot은 1급**). 필드: 이름·
  별칭·설명·노트·Custom Details(k/v, `codex.detail`)·Category·Tags·Relations(child).
  탐지 = **이름/별칭 문자열 매칭 + 영어 복수형**(밑줄·멘션 카운터). **임베딩·의미검색
  전혀 없음** [CONFIRMED].
- **Codex 주입 6단계**(최고가치) [CONFIRMED]: ① 현재 beat + **이전 본문**의 멘션 ②
  수동 참조(+Codex) ③ POV 항목 ④ global(Always Include) ⑤ 위 항목들의 related child
  ⑥ 빈 항목 제외. 최종 정렬 Global→Type→Name. per-entry AI-Context 4상태(Always/
  When-detected(기본)/Don't-when-detected/Never). *MINT ContextAssembler.selectCards가
  이미 이 일을 — 단 더 똑똑한 축(엔티티·상태·시점 차단)이고 **자동 탐지**라 수동
  태깅 불요(리뷰가 지적한 NovelCrafter 셋업 고통을 MINT가 구조적으로 해결).*
- **Scene Beats** [CONFIRMED]: `/`→beat 지시 → ▶ 산문 확장(~400단어). 인라인 `[지시]`
  (`[slow down]`·`[expand dialogue]`). 컨텍스트 = beat + 이전 씬 요약(story so far) +
  현재 씬 앞 본문 + Codex + POV. 결과: Apply/Retry/Discard/Section.
- **Prompt DSL(핵심)** [CONFIRMED]: `{ }` 표현식·함수·`include()`·`input()`·`local()`·
  Presets(프롬프트+모델)·Personas·Defaults(Account→Series→Novel)·Prompt Library. 변수
  카탈로그가 곧 컨텍스트 모델: `storySoFar`·`textBefore`/`wordsBefore(n)`·`scene.summary`·
  `codex.*`·`pov.*`·`novel.fullText`. **Prompt Preview**(전송 전 조립 확인 = 토큰 절약).
- **Sections** [CONFIRMED]: 씬 내 "AI에서 숨김" 블록(노트·거부 콘텐츠 격리·대안 버전).
- **Revision History** [CONFIRMED]: 씬 3분마다 자동 버전, Restore.
- **일관성 검사 없음** [CONFIRMED, 2026 리뷰 다수]: Codex는 참고 문서일 뿐 **강제/검증
  레이어 아님** — 생성이 Codex와 모순돼도 막지 않음. *→ MINT ConsistencyChecker가 차별점.*
- **Chat(Tinker)**: 원고·Codex 인지 대화, 좋은 사실은 **Codex에 되쓰기**.
- 출처: novelcrafter.com/help/faq/ai-and-prompting/codex-context-in-prompting,
  /docs/ai/prompt-functions, /help/docs/codex/codex-tracking, /blog/may-2025-new-prompting-system-update.

### 3.3 Sudowrite (심층) — "Story Bible cascade + Saliency Engine + Chapter Continuity"
- **모델·라우팅** [CONFIRMED]: 자체 파인튜닝 **Muse 1.5**(소설 특화, 기본) + Ballad
  ("Excellent") + 서드파티 애그리게이터(Claude/GPT/Gemini/DeepSeek 등, **사용자 선택**).
  크레딧 = 읽은+쓴 단어×모델(같은 200단어 Write가 GPT-5-nano 70 vs Claude Opus 8000+).
- **모든 AI 액션 = History 카드**(오른쪽 열) → Insert(커서에 삽입, 편집 전 **보라색**)/
  Star/copy. *= 비파괴 "제안 후 반영" UX의 정석.*
- **Write** [CONFIRMED]: Auto(이어쓰기)/Guided(방향 입력·3제안)/Tone Shift(톤 강제).
  Creativity 슬라이더·카드 1–6개·길이. **Expand/Rewrite/Describe/Quick Edit/Brainstorm/
  Visualize**는 selection 메뉴. Rewrite 하위모드: Rephrase/Shorter/More Descriptive/
  **Show Not Tell**/More Inner Conflict/More Intense/Customize. Describe: 5감 카드(컨텍스트
  **좁음** — 문단+앞 200자, Story Bible 안 봄). **Quick Edit**: 인라인 취소선 accept/
  reject/refine(**무료**). Brainstorm: **고립**(Story Bible 안 봄).
- **Story Bible(핵심) = cascade 의존 그래프** [CONFIRMED]: Braindump→Synopsis(spine)→
  Genre/Style→Characters/Worldbuilding→**Outline**(장 요약)→**Scenes**(장별 beat)→
  **Draft**(장 산문 스트리밍). 각 섹션이 위 섹션에서 생성. Characters 특성(Pronouns·
  Personality·Dialogue Style 등)이 "AI가 그 인물을 쓰는 법"에 주입. *MINT 요약 피라미드는
  read-side 대응 — write-side(outline→scene→prose 생성)는 MINT에 없음(= Scene Beat 갭).*
- **Saliency Engine(핵심)** [CONFIRMED 동작 / HOW=UNKNOWN]: 숨은 사전 처리 — Characters/
  Worldbuilding 카드 중 **현재 과업에 관련된 것만** 노출("늑대 형태면 카키바지 안 넣음").
  visibility 토글로만 제어, 플러그인 `{{characters}}`(필터)vs`{{characters_raw}}`(전량).
  임베딩/LLM/키워드 여부 비공개. *= MINT ContextAssembler.selectCards의 상위 개념 — 단
  MINT는 결정론(창 언급+관계 인접)이라 설명 가능·시점 차단.*
- **Chapter Continuity(컨텍스트 예산 정책)** [CONFIRMED]: Write/Draft가 링크된 이전
  문서에서 **최대 20,000 단어**(최대 25 문서, 최신 우선) + 현재 문서 **20,000 단어**.
  **고정 드롭 순서**(초과 시 위부터): Worldbuilding→Characters→이전 장 본문→Outline
  요약→Genre→Key Details→Tone→Style→현재 문서 앞 본문→하이라이트. **chiclets**가 어느
  문서·몇 단어를 읽었는지 공개. *= MINT 예산 삭감 순서(사건→카드→요약→C)의 정식 대응.*
- **Chat "Allow edits"(경쟁사 중 가장 Agent에 근접)** [CONFIRMED]: 두 모드 — Chat-only
  (무료·무제한 브레인스톰/피드백) / **Allow edits(크레딧, 문서·Story Bible 편집·코멘트·
  피드백 실행, "사용자가 먼저 승인하는 multi-step 계획 실행")**. *→ MINT Agent 방향을
  검증. 단 Sudowrite는 tool 루프가 아니라 승인형 편집 — MINT는 tool-based 조회+편집으로 더 나감.*
- **Feedback/Beta Read**: 여백 코멘트(3 페르소나 Maya/Anton/Joan). **My Voice**: **실제
  개인 모델 학습**(≥1000단어, <2분) — MINT PLAN §15 LoRA 아이디어의 상용 선례.
- 플러그인 변수 = 컨텍스트 모델 노출: preceding_text·highlighted_text·previous_document_text·
  braindump·genre·style·synopsis·characters(/_raw)·worldbuilding(/_raw)·outline·
  scene_summary·chapter_scenes·is_story_bible_active·prompt_N_result(다단 체이닝).
- 출처: docs.sudowrite.com + github.com/sudowrite/docs-control(스토리 바이블·Story
  Smarts·Plugins 페이지), sudowrite.com/muse.

### 3.4 기타 (요약)
- **DreamGen** [CONFIRMED]: RP/스토리 특화 자체 모델(Opus/Lucid), `<setting>`/`<instruction>`
  태그로 "다음 몇 문단에 일어날 일" 조종. Continue vs Instruction.
- **Squibler** [CONFIRMED]: Smart Writer(목표 설정→반복 개선), outline(beats→chapter→scene),
  Elements 보드(연속성), **각본/스크린플레이** 포맷 강점.
- **Raptor Write vs Subtxt/Muse** [CONFIRMED, 브리프 혼동 정정]: 별개 제품. Raptor
  Write=무료·브라우저 로컬·OpenRouter BYOK, 저마찰 brainstorm→outline→draft. **Subtxt
  with Muse**=Dramatica 이론 기반 **스토리 구조 엔진**(Storyform/Storypoint), "Muse"는
  brainstorm 레이어. *프레임워크 기반 아웃라이닝.*
- **AI Dungeon** [CONFIRMED]: 인터랙티브 픽션. **Memory System 이원**: Auto-Summarization
  (롤링 요약) + **Memory Bank(임베딩 벡터 검색)**. Story Cards(키워드 트리거 로어북).
  Scripting 훅. *= 키워드 + 임베딩 **하이브리드** 검색(NovelAI는 순수 키드).*

## 4. 경쟁사 기능 전체 Feature Matrix
| 기능 | NovelAI | NovelCrafter | Sudowrite | AI Dungeon | **MINT(현재)** |
|---|---|---|---|---|---|
| 자체 온디바이스 모델 | 클라우드 자체 | ❌ BYOK | 클라우드 자체 | 클라우드 | ✅ **완전 로컬 MLX** |
| 인라인 자동완성(고스트) | continuation | Continue | Write | 액션 루프 | ✅ 고스트+대화모드 |
| Story Bible/Codex/Lorebook | Lorebook(키드) | Codex(6타입,문자열) | Story Bible | Story Cards | ✅ CharacterCard+자동감지 |
| **자동 엔티티 감지** | ❌(수동) | 부분(문자열/detect) | Import 시 | 부분 | ✅ **유정성 신호(P100%)** |
| 관계/상태 시간축 | ❌ | Relations(정적) | 부분 | ❌ | ✅ **StateDelta·시점 fold** |
| 존대/화자(한국어) | ❌ | ❌ | ❌ | ❌ | ✅ **존대 매트릭스** |
| 사건/인과/플롯 그래프 | ❌ | Matrix(수동) | ❌ | ❌ | ✅ **정본사건·인과·PlotThread** |
| 연속성/일관성 검사 | ❌ | ❌ | 부분(POV/시제) | ❌ | ✅ **ConsistencyChecker** |
| Context Viewer(투명성) | ✅ 상세 | ✅ Preview | 부분 | ❌ | ✅ ContextReport/인스펙터 |
| 컨텍스트 제어(pin/hide) | 우선순위/예약 | Sections/inclusion | Bible 토글 | Memory | ✅ Pin/Exclude |
| 의미 검색(임베딩) | ❌ | ❌ | 부분 | ✅ Memory Bank | ❌(엔티티 앵커) |
| **Agent/Tool 루프** | ❌ | ❌ | ❌ | Scripting | ❌ → **이번 재설계** |
| 편집 diff/승인 | Retry | Apply/Retry | 카드 | Retry | ❌(고스트만) |
| 버전/체크포인트 | Story history | 3분 자동 | 히스토리 | ❌ | ⌘Z+스냅샷 |

관찰: **아무도 진짜 Agent(tool 루프)가 없다.** MINT는 Story Intelligence 깊이에서
이미 앞서고(자동 감지·상태 시간축·존대·인과·일관성), Agent를 얹으면 카테고리 차별화.

## 5. 경쟁사 기능에서 배울 점
1. **NovelAI 조립 알고리즘** = MINT ContextAssembler의 정식화 참고: 예약 → 우선순위 배치
   → 단계적 Trim → 드롭. MINT 예산 삭감 순서(사건→카드→요약→C)를 이 형식으로 정련.
2. **NovelAI/NovelCrafter Context Viewer/Preview** = 신뢰의 핵심 UX. MINT ContextReport를
   Agent에도 확장(무엇을 왜 넣었나) — "설명 가능한 Agent".
3. **NovelCrafter 6단계 Codex 주입 + related-child 확장** = MINT의 "활성 인물의 1촌
   관계 인접" 랭킹과 동형 — MINT는 관계를 StateDelta로 이미 앎.
4. **NovelCrafter DSL/Prompt Preset** = 사용자 프롬프트 커스터마이즈의 상한. MINT는
   Agent + MINT.md로 더 일반적으로(하드코딩 대신 지침) 해결.
5. **일관성 검사 부재(NC/NAI)** = MINT ConsistencyChecker가 명확한 우위 — Agent로
   `check_consistency` + 심화(설정 모순은 LLM)로 확장.
6. **Aider architect/editor 분리** = "장면 기획 모델 vs 산문 편집 적용 모델" — MINT
   단일 모델에선 2-패스(계획→패치)로 흡수.
7. **AI Dungeon 하이브리드 검색** = 키드+임베딩. MINT는 엔티티 앵커가 1차, semantic은
   측정으로 이길 때만(PLAN §15) — 하이브리드 여지 인지.
8. **자동 감지의 가치**(NC 셋업 고통) = MINT의 자동 인물 감지·Entity Resolution이 진짜
   차별점 — Agent가 이를 tool로 노출하면 "설정 안 해도 아는" 경험.

## 6. MINT에 가져올/제외할 기능 (이유 명시)
- **반드시(재해석)**: Context Viewer→Agent 확장(NAI/NC). Scene Beat→`continue_writing`/
  `write_from_beat`(NC). Rewrite/Describe/Expand/Shorten→selection 편집 tool(Sudowrite).
  Story-so-far 요약 컨텍스트→이미 있음(요약 피라미드). 명령형 `{지시}`/`[지시]`→Agent
  자연 수행.
- **Agent가 자연히 수행(별도 기능 불요)**: Brainstorm·Chat·Character/Plot/Continuity
  "analysis" 버튼들·Twist·"Poke the Muse" → 전부 Agent Loop + primitive 조합. **거대
  analyze_* 버튼을 만들지 않는다**(브리프 원칙).
- **MINT식 재해석**: Lorebook 수동 키/우선순위 → **자동 엔티티 앵커 + Pin/Exclude**
  (수동 태깅 제거). Codex Relations → StateDelta/RelationDelta(시간축). Sections(hide)
  → Pin/Exclude·"검토 필요".
- **제외**: BYOK/클라우드 모델 라우팅(완전 로컬 위배). 이미지 생성(Director Tools/
  Visualize) — 범위 밖. Dramatica 구조 엔진(과한 이론 결합). 각본 포맷(도메인=소설).
- **장기**: semantic_search(임베딩, 측정 후). Import Novel식 대량 자동 바이블(이미 자동
  감지 있음 — 대작 초기 인덱싱 UX로). Prompt DSL(고급 사용자용, MINT.md로 대체 가능).

---

## 7. 기존 기능 → Agent Capability 변환표 [코드확인 기반]

원칙: **경쟁사 기능을 복제하지 않고 primitive로 분해**. 아래는 MINT의 기존 자산이
어떤 Tool로 승격되는지 (재사용 지점 명시).

| 경쟁사 기능(문제) | 분해된 Capability | MINT 재사용 코드 | 분류 |
|---|---|---|---|
| Character Analysis | find_character, get_character_state, get_character_dialogues, get_character_events, read_scene + LLM 판단 | `KnowledgeSnapshot.stateAt`/`conversations(involving:)`/`eventIndexByCharacter`/`lastAppearance` | **C(Agent Workflow)** |
| Continuity / Consistency check | ConsistencyChecker(죽은인물·존대붕괴) + Agent 심화 | `ConsistencyChecker.check`, `stateAt`(생사), `honorific` | B(tool) + C |
| Codex/Lorebook 주입 | 활성 엔티티 앵커 검색 → 카드 조립 | `ContextAssembler.selectCards`/`headerText`, `KnowledgeSnapshot` | **이미 존재**(자동완성) → tool 승격 |
| Describe/Expand/Rewrite/Shorten | selection + 프롬프트 스타일 → 생성 | `CompletionEngine.generateOneShot`, selection API(신규) | A(edit)+생성 tool |
| Brainstorm/Chat | Agent Loop + read/search tools | Agent Runtime(신규) + 기존 질의 | C |
| Timeline/Story arc 보기 | get_timeline, get_plot_threads | `chronologicalSceneOrder`/`eventChronoOrder`/`plotThreads`/`flows` | B(tool) |
| Relationship map | get_relation, get_relation_history | `relation(from:to:before:)`/`relationHistory` | B(tool) |
| Scene from beat | read_outline + write → patch | `DocumentOutline`, 편집 API, 생성 | C |
| Manuscript search | search_text (결정) / semantic_search (신규) | `EntryStore.search` / (임베딩 신규) | A / B |

핵심: **거대 `analyze_character` 대신 primitive 조합**. MINT의 질의 메서드가 이미
그 primitive의 대부분이다.

---

## 8. Proposed Writing Tool Catalog (초기 15~25개, 우선순위 포함) [코드확인 기반]

표기: **[P]**rimitive(결정·빠름) / **[I]**ntelligence(NLP·모델·임베딩) / side-effect=✎.
각 tool: 목적 · 입력 · 출력 · side-effect · 재사용 코드 · 예상 latency · Qwen 선택 난이도.

### Project / Read (전부 [P], 결정론적, <5ms)
1. `list_documents` — 프로젝트 문서·폴더 트리. in: {folder?}. out: [{id,title,kind,folder}].
   재사용 `EntryStore.entries/folders`. Qwen 선택 쉬움.
2. `get_active_document` — 현재 문서 메타(제목·장르·kind·씬 수). 재사용 `activeEntry`+`DocumentOutline`.
3. `get_outline` — 헤딩→장/절/씬 트리(제목·요약·씬해시·범위). 재사용 `DocumentOutline`+`summariesByHash`+`sceneMetaByHash`.
4. `read_scene` — 씬 원문(sceneHash 또는 index). in:{sceneRef}. out:{text,headingPath,range}. 재사용 `DocumentOutline.scenes`+body slice.
5. `read_range` — UTF-16 범위 원문. side-effect 없음. 재사용 body slice.
6. `get_selection` — 현재 selection 텍스트·범위. 재사용 에디터 selection API(신규 브릿지).

### Search (P/I 혼합)
7. `search_text` [P] — 결정 부분 문자열(전역/문서). 재사용 `EntryStore.search`/`SearchJump`. <10ms.
8. `find_character_mentions` [P] — 이름·별칭 원문 위치. 재사용 `nameIndex`+스캔.
9. `semantic_search` [I] — 의미 유사 씬(임베딩). **신규**(NLEmbedding 또는 MLX 임베더, §15).
   측정으로 이길 때만(PLAN §15) — MVP 후보 아님.

### Story Knowledge (전부 [P] — `KnowledgeSnapshot` 질의를 그대로 노출, <5ms)
10. `find_character` — 이름/별칭→카드(+등록여부·신뢰). 재사용 `characters`+`EventParser.nameIndex`.
11. `get_character_state` — `state_at(커서/씬)`(위치·감정·관계·목표·생사). 재사용 `stateAt`. **핵심**.
12. `get_character_knowledge` — 그 시점 앎(+회상 시 chrono fold). 재사용 `knowledge`/`knowledgeChrono`.
13. `get_character_events` — 참여 사건(담화순). 재사용 `eventIndexByCharacter`+`lastAppearance`.
14. `get_character_dialogues` — 참여 대화·말투·예문. 재사용 `conversations(involving:)`+`speechProfile`.
15. `get_relation` — (A→B) 관계+이력+존대. 재사용 `relation`/`relationHistory`/`honorific`.
16. `get_timeline` — 사건 시간순/담화순(+Conflict). 재사용 `eventChronoOrder`/`chronologicalSceneOrder`.
17. `get_plot_threads` — 플롯 스레드·상태·멤버. 재사용 `plotThreads`/`threads(of:)`/`causes/effects`.
18. `get_context_at_cursor` — 커서의 서사 좌표+주입될 카드(=자동완성이 보는 것). 재사용 `position(at:)`+`assembleWithReport`.

### Intelligence (모델 필요, [I])
19. `identify_speaker` [P/I] — 커서 다음 화자 추정. 재사용 `expectedSpeaker`(결정) / 모호 시 LLM.
20. `analyze_scene` [I] — 씬 요약·유형·시점·장소. 재사용 `BackgroundIndexer.analyzeScene`(이미 public).
21. `extract_events` [I] — 씬 사건+델타. 재사용 `extractEvents`(이미 public).
22. `check_consistency` [P] — 죽은인물·존대붕괴. 재사용 `ConsistencyChecker.check`.

### Writing / Editing (✎ side-effect — 전부 diff 경유)
23. `continue_writing` [I] — 이어쓰기 초안(고스트 아님, 블록). 재사용 `generateOneShot`/continuation.
24. `rewrite_selection` [I] ✎ — 선택 재서술(톤/길이/보여주기 지정). 생성 + `propose_patch`.
25. `propose_patch` [P] ✎ — 범위 치환/삽입/삭제를 **diff 제안**으로. 재사용 에디터 편집 API + `SearchJump`.

우선순위(MVP→후속): **P0** 1–5,7,10–18,22 (조회·검색·일관성 — 전부 기존 코드 승격,
side-effect 없음) → **P1** 6,19–21,23–25(생성·편집·diff) → **P2** 9 semantic_search.
설계 원칙: **primitive를 적게, Agent가 조합**. 20/21은 tool로도 두지만 대개 Agent가
11–15를 조합해 "character analysis"를 workflow로 수행한다.

---

## 9. Qwen3.6 Agent Runtime 설계 [코드확인 + 검증된 API 기반]

### 9.1 Tool Calling 방식 — 결론: 네이티브 우선 + 폴백 [코드/웹 확인]
- **가능**: mlx-swift-lm 3.31.3 `UserInput(chat:tools:[ToolSpec]?)` (모든 이니셜라이저),
  Qwen3.6 챗 템플릿이 Hermes 스타일 tool use 내장(`<tools>` JSON → `<tool_call>{...}`),
  `generate` 스트림 `.toolCall` 케이스 존재. `ToolSpec = [String: any Sendable]`(JSON schema dict).
- **리스크**: 2bit/A3B 공격적 양자화에서 JSON 형식 붕괴 가능(§18). thinking 모드와
  tool call 상호작용(현재 코드는 thinking off).
- **설계**: (1) 1차 = 네이티브 Hermes tool call(`ToolCallProcessor`가 `<tool_call>`
  누적). (2) **lenient-parse/strict-validate 래퍼**(EventParser 철학): 스트림에서
  `<tool_call>` 텍스트를 직접 파싱→JSON 관대 복구→Tool Registry 스키마 검증→실패 시
  1회 repair 프롬프트. (3) **폴백 프로토콜**: 네이티브 실패율이 높으면 단순 줄 형식
  (`TOOL: name {json}`) 또는 제약 디코딩. → **ADR-1**.

### 9.2 Agent Loop (온디바이스 예산 내)
```
UserRequest → [Agent Session 구성: system(도구목록+MINT.md) + 대화이력 + 요청]
  loop (step ≤ maxSteps=8):
    Qwen3.6 생성(tools=registry.specs, thinking=요청유형별)
    if toolCall: 파싱·검증 → ToolExecutor(비동기, 캐시) → toolResult 메시지 append
    else: finalText → 종료
  종료: Final Response | Manuscript Patch(diff) | 실패(부분 결과 + 사유)
```
- **최대 step 8**(온디바이스 지연). **무한루프 방지**: 같은 tool+같은 args 연속 3회 →
  강제 종료 + 관찰 요약 주입. step 예산 초과 → "지금까지 찾은 것"으로 마무리 프롬프트.
- **실패한 tool**: 결과에 error 필드로 넘겨 Agent가 복구(다른 tool·인자 수정). 크래시 금지.
- **취소**: 기존 협조 취소(`Task.isCancelled`) 그대로 — 사용자가 중단하면 다음 청크에서 정지.
  자동완성 예측이 도착하면 Agent 생성을 선점(단일 모델 규율) — 또는 Agent 모드 중엔
  고스트 예측 보류(모드 배타, §12).
- **Streaming**: 텍스트 청크 + tool call/result를 UI에 스트림(진행 표시, §12).

### 9.3 Tool Registry / Schema / Execution
- `WritingTool` 프로토콜: `name`, `description`(한국어), `parameters`(JSON schema=ToolSpec),
  `sideEffect: Bool`, `func run(args, ctx: AgentContext) async throws -> ToolResult`.
- `ToolRegistry`: 등록·`specs`([ToolSpec] 생성)·이름→tool. `AgentContext`: 활성 문서
  스냅샷(값복사) + `KnowledgeSnapshot` + 편집 브릿지(MainActor) + 취소 토큰.
- **Tool Result 캐싱**: (tool, args, 지식세대) 키 메모(같은 세션 재조회 skip) — 기존
  해시 메모 철학 재사용.
- **Background Tool 실행**: 조회 tool은 값복사 스냅샷에서 실행(디스크·MainActor 무접촉).
  편집 tool만 MainActor 브릿지.

### 9.4 Agent Session / History / Context Budget
- `AgentSession`: 메시지 배열(user/assistant/tool) + 토큰 카운트 + 참조 지식세대.
- **Context Budget**: 시스템(도구+MINT.md) 고정 + 대화이력 + tool result. 예산 초과 시
  **Compression**: 오래된 tool result를 "요지 1줄"로 접기(원본은 세션 로그 보존),
  오래된 assistant 추론 요약. → §11.

### 9.5 OpenCode ↔ MINT 대응
| Coding Agent | MINT |
|---|---|
| Repository | Writing Project(폴더/저널 집합) |
| Source File | Chapter/Document(=`JournalEntry`, 헤딩=씬) |
| Symbol | Character/Location/Event(엔티티) |
| Code Search / grep | `search_text` / `find_character_mentions` |
| LSP / go-to-def | Story Intelligence 질의(`KnowledgeSnapshot`) |
| Compiler error | Continuity Conflict(`ConsistencyChecker`·chronoConflicts) |
| Git Diff | Manuscript Diff(propose_patch) |
| AGENTS.md/CLAUDE.md | **MINT.md**(작품별 집필 지침·금기·톤) |
| Edit Tool | `propose_patch` |
| Permission gate | side-effect tool 승인 + Pin/Exclude(기존) |
| Undo/checkpoint | 에디터 ⌘Z + 스냅샷(기존) |

참고 근거(웹): OpenCode는 `streamText` 루프 + `stopWhen`(step 상한) + Zod 스키마 tool
(description+input schema+execute) + Permission.ask(plan/build 모드) + ~90% 컨텍스트
compaction + step 전 Git-tree 스냅샷. Aider = repo map(심볼 그래프+PageRank) + SEARCH/
REPLACE 편집 포맷 + architect/editor 분리. Cline = Plan/Act + XML tool + MCP. Claude
Code = 3단 루프 + auto-compaction + `/rewind`(3 모드) + CLAUDE.md.

---

## 10. Story Intelligence Architecture (Agent Infrastructure로 재정의) [코드확인]

이미 통합돼 있다 — 재설계는 "다른 제품 기능"이라는 오해를 걷어내는 것.
```
Manuscript(entries.json body)
  → DocumentOutline(결정 파싱) → 씬(해시 앵커)
  → BackgroundIndexer(증분·2단·게이트) → KnowledgeSidecar(v7)
  → makeSnapshot(+overrides) → KnowledgeSnapshot(단일 인메모리 인덱스)
        Entities/Characters · Events · StateDeltas · Knowledge/Relation ·
        Segments · CanonicalEvents · Causal · ChronoOrder · Flows · PlotThreads ·
        Conversations · SceneSummaries
  → 소비자 4곳: ① UI(NarrativeView·CharacterBibleView) ② **Agent Tools(신규)**
     ③ 자동완성 Retrieval(ContextAssembler) ④ ConsistencyChecker
```
- 결정: **중복 분석·별도 데이터 소스 만들지 않는다.** Agent tool은 `KnowledgeSnapshot`
  질의를 얇게 감싼다(§8의 10–18). 자동완성과 Agent가 **문자 그대로 같은 스냅샷**.
- 갱신은 기존 증분 파이프라인 그대로. Agent가 "지금 읽기"(`requestPass`) 트리거 가능.

---

## 11. Context Management 설계 [코드확인 + 경쟁사/코딩에이전트 차용]
- **원고 전체를 매 요청에 넣지 않는다**(온디바이스 전제 — PLAN §1 거대 컨텍스트 비판).
  Agent는 tool로 조회. 이는 Sudowrite Chapter Continuity(20k단어 슬라이딩 창)·NovelCrafter
  요약 컨텍스트보다 한 걸음 더 — **필요할 때만 조회**.
- **레이어**: (A) 시스템=도구 스키마+MINT.md(작품 지침) — 거의 불변, KV 친화.
  (B) 세션 대화이력. (C) 최근 tool result. — ContextAssembler의 A/B/C 철학을 세션에 재적용.
- **Budget & Compression 정책**(경쟁사 정식화 차용):
  - **Compaction 임계 ~90% 사용가능 컨텍스트**(OpenCode 패턴): 넘으면 오래된 tool
    result·추론을 "요지 1줄"로 접는다(원본은 세션 로그 보존). 자동완성 요약 피라미드의
    "해상도 하향"과 같은 개념.
  - **고정 드롭 우선순위**(Sudowrite Chapter Continuity 대응): 초과 시 버리는 순서 =
    오래된 tool result → 과거 추론 요약 → (마지막) 최근 tool result·현재 요청. 사용자
    Pin 항목은 보존(기존 Pin/Exclude).
  - **상태 외부화**(Claude Code 패턴): 세션 진행/결정을 **story-state(세션 스크래치)**로
    외부화 — compaction이 일어나도 재조회로 복구(plot state 유실 방지).
- **Session Memory**: 세션 종료 시 핵심 결정을 MINT.md에 반영 제안(사용자 승인).
- **시점 차단 유지**: Agent 조회도 커서 이전만(기존 `before:` 질의) — 회상 집필 시 미래
  누출 차단이 tool 레벨에서 자동 성립. (경쟁사엔 이 시점 차단 개념 자체가 없다.)

---

## 12. Agent UX 설계 [신규 + 기존 재사용 + 경쟁사/코딩에이전트 차용]
- **진행 표시**(스트리밍, OpenCode fullStream 대응): "민수 찾는 중… → 관련 씬 8개
  읽는 중… → 이전 대사 31줄 확인 중… → 상태 분석 중" = tool call/result를 사람이 읽는
  줄로. tool마다 어느 씬·몇 단어를 읽었는지(Sudowrite **chiclets** 대응) 노출 —
  ContextReport 렌더 재사용 → **설명 가능한 Agent**(NovelAI Context Viewer의 Agent판).
- **편집은 파괴적 금지가 기본**: `propose_patch` → **Diff 표시 → Accept/Reject/Refine →
  Apply**. 인라인 소규모 편집은 Sudowrite **Quick Edit**식 취소선(원본 유지, accept/reject)
  또는 History 카드식(비파괴 제안, 삽입은 사용자). 다중 씬 편집은 씬별 diff 목록
  (Multi-file diff 대응). `SearchJump`으로 원문 점프.
- **Plan/Act(권한) 모드**(OpenCode plan/build · Cline Plan/Act 대응): 기본 = **읽기 전용
  Agent**(조회·조언, side-effect 없음) ↔ 명시적 **편집 허용 모드**(Sudowrite Chat "Allow
  edits"처럼 승인형 multi-step). side-effect tool은 세션 정책(항상 물음/이 세션 허용/자동).
- **체크포인트/되돌리기**(Claude Code `/rewind` 대응): 편집 적용 전 스냅샷 → 대화·원고
  각각 되돌리기. 에디터 ⌘Z + 기존 스냅샷 인프라 재사용.
- **2-패스 편집**(Aider architect/editor 대응, 단일 모델): Agent가 먼저 "무엇을 어떻게
  고칠지" 계획(자연어) → 그 다음 patch 생성 — 소형 모델의 편집 정확도 보강.
- **컨텍스트 제어**: Pin/Exclude로 강제 포함/제외(기존 오버라이드) = NovelAI 우선순위·
  NovelCrafter Sections·Sudowrite visibility 토글의 통합 대응.
- **모드 관계**: Agent 챗 패널(사이드바 신규 섹션) ↔ 고스트 자동완성은 **공존**(같은 지식,
  다른 진입점). Agent 실행 중엔 고스트 예측 일시 보류(단일 모델 경합 방지).

---

## 13. 유지할 것 [코드확인]
- Story Intelligence 전체(추출·질의·사이드카·스냅샷·오버라이드 분리)·시점 차단·해시 메모.
- `CompletionEngine` 단일 모델 actor·KV 재사용·`generateOneShot` 패턴.
- 자동완성 고스트·게이트·대화 모드·ContextReport·Pin/Exclude·AcceptanceMetrics.
- NarrativeView·CharacterBibleView(순수 소비자).
- 결정론 우선(격조사·귀속·존대)·lenient/strict 파싱 철학.

## 14. 리팩터링할 것
- `BackgroundIndexer`의 순수 추출 함수들을 **StoryToolkit**(가칭)으로 명시 그룹화(이미
  public·nonisolated이라 이동 최소).
- `KnowledgeSnapshot` 질의들에 **안정 식별자(sceneRef/characterRef)** 파라미터 어댑터
  추가(Agent가 UUID 대신 이름/해시로 부를 수 있게).
- `ContextAssembler`의 엔티티 앵커 선택 로직을 재사용 가능한 **retrieval 함수**로 노출
  (자동완성·Agent·semantic A/B 공용).
- 에디터 selection/patch 브릿지 인터페이스 정리(Agent 편집 실행 지점).

## 15. 새로 구현할 것
- `AgentRuntime`(Loop·Registry·Executor·Session·Budget·Compression) — §9.
- `WritingTool` 20여 종 얇은 래퍼 — §8.
- Agent 챗 UI(사이드바 섹션) + 진행 스트림 + Diff/Accept UX — §12.
- `MINT.md`(작품별 집필 지침) 로드·주입.
- (P2) `semantic_search` 임베딩 스택.

## 16. 제거할 것
- **최소화**(기본값은 삭제 아님, CLAUDE.md 지시). 후보: 없음(전부 승격·유지). 단
  `instruct` 자동완성 경로는 Agent와 중복 시 정리 검토(측정 후).

## 17. 단계별 Migration Plan
1. **M-A0 인프라 승격**: `WritingTool`/`ToolRegistry`/`AgentContext` + 조회 tool(§8 P0)
   구현(전부 기존 코드 래핑, side-effect 없음). 벤치: tool 호출 정확도(Qwen3.6).
2. **M-A1 Read-only Agent**: Loop + 네이티브 tool call + 폴백 파서 + 챗 UI + 진행 스트림.
   "질문 답변"만(편집 없음). §18 신뢰도 측정.
3. **M-A2 편집**: `propose_patch`·`rewrite_selection`·`continue_writing` + Diff/Accept UX.
4. **M-A3 세션·컨텍스트**: Budget·Compression·Session Memory·MINT.md.
5. **M-A4(옵션)**: semantic_search A/B, multi-scene diff, permission 정책 고도화.

## 18. 기술적 위험 요소
- **양자화 하 tool-call 형식 신뢰도**(2bit MINT/A3B) — 최대 미지수. 측정 선행, 폴백 필수.
  Qwen3.6(Peppermint) 권장(A3B가 형식 준수 유리 추정 [추론]).
- **지연**: multi-step tool loop × 온디바이스 디코딩 → 수 초. 조회 tool 결정·캐시로 흡수,
  step 상한, 진행 표시로 체감 완화.
- **단일 모델 경합**: Agent vs 자동완성 vs 백그라운드. 선점 규율 확장 필요.
- **Diff 신뢰성**: 소형 모델의 부정확 편집 → 항상 사용자 승인 게이트.
- **컨텍스트 예산**: 긴 세션 → Compression 필수. 잘못 접으면 Agent가 맥락 상실.
- **스키마 드리프트**: 사이드카 v7 → tool 결과 형태 결합. 파생 캐시 규율로 흡수.

## 19. 구현 우선순위
- P0(가치/비용 최고): §8의 조회·검색·일관성 tool(전부 승격) + M-A0/M-A1.
- P1: 편집 tool + Diff UX(M-A2).
- P2: 세션 메모리·MINT.md·semantic_search.

---

## Recommended MVP
**Read-only Writing Agent (M-A0 + M-A1)**: 사이드바 Agent 챗. tool = `get_active_document`,
`get_outline`, `read_scene`, `search_text`, `find_character`, `get_character_state`,
`get_character_events`, `get_character_dialogues`, `get_relation`, `get_timeline`,
`check_consistency`, `get_context_at_cursor` (전부 기존 코드 래핑, side-effect 없음).
네이티브 Hermes tool call + lenient/strict 폴백 파서, step ≤ 6, 진행 스트림.
편집은 MVP에서 제외(제안만: "이 대사가 민수답지 않다" 같은 조언). 근거: 위험(파괴적
편집)은 미루고, MINT의 최대 자산(Story Intelligence)을 최소 신규 코드로 Agent에 연결해
"프로젝트를 이해하는 Agent"의 핵심 가치를 먼저 검증.

## Example Agent Traces (≥10) [코드확인 tool 기반]
1. "민수의 이 대사 자연스러워?" → get_selection → identify_speaker → find_character(민수)
   → get_character_state(before=커서) → get_character_dialogues(민수) → get_relation(민수→상대)
   → 판단 텍스트.
2. "3장까지 민수가 아는 걸 정리해줘" → get_outline → find_character → get_character_knowledge(before=3장끝) → 요약.
3. "지금 흐름이 뭐였지?" → get_context_at_cursor(position) → get_plot_threads → 설명.
4. "서연이랑 민준 관계 어떻게 변해왔어?" → find_character×2 → get_relation_history → 타임라인 서술.
5. "죽은 인물이 말하는 데 없어?" → check_consistency → (있으면) read_scene로 확인 → 목록.
6. "이 장면 요약해줘" → get_active_document → analyze_scene(현재 씬) → 요약.
7. "민수 처음 등장이 어디야?" → find_character → get_character_events(첫 사건) → read_scene → 위치.
8. "복선/미해결 플롯 뭐 있어?" → get_plot_threads(status=OPEN/ACTIVE) → 설명.
9. "이 문단 좀 더 보여주기식으로" (편집 MVP+1) → get_selection → rewrite_selection → propose_patch → Diff.
10. "이 대화 이어서 써줘" → get_context_at_cursor → identify_speaker → get_character_dialogues(말투) → continue_writing → 블록 제안.
11. "병원 나오는 장면 다 찾아줘" → search_text("병원") → get_outline로 씬 매핑 → 목록+점프.
12. "이 인물 지금 감정 상태가 앞이랑 안 맞는 것 같아" → find_character → get_character_state(여러 위치) → get_character_events → 대조.

## Architecture Decision Records
- **ADR-1 Tool Protocol**: Decision=네이티브 Hermes tool call 우선 + lenient/strict 파서
  + 줄형식 폴백. Alt=순수 XML/JSON 커스텀 프로토콜, 제약 디코딩. Reason=챗 템플릿이 이미
  지원·`.toolCall` 존재, 기존 파싱 철학 재사용. Trade-off=양자화 형식 붕괴 시 폴백 유지비.
- **ADR-2 Story Intelligence 공유**: Decision=Agent tool은 `KnowledgeSnapshot` 질의를
  얇게 래핑, 새 데이터 소스 금지. Alt=Agent 전용 인덱스. Reason=단일 소스·중복 분석
  회피·자동완성과 일치. Trade-off=스냅샷 스키마에 tool 결합.
- **ADR-3 편집 = Diff 제안 기본**: Decision=propose_patch→Diff→Accept. Alt=직접 적용.
  Reason=원문이 유일한 진실·파괴적 편집 위험·소형 모델 부정확. Trade-off=명시 허용 모드로 완화.
- **ADR-4 Agent·자동완성 공존**: Decision=별도 진입점, 같은 지식, 단일 모델 선점 조율.
  Alt=자동완성 대체. Reason=예측 엔진은 MINT의 검증된 자산. Trade-off=모델 경합 관리.
- **ADR-5 온디바이스 Retrieval**: Decision=엔티티 앵커 질의 우선, semantic_search는 측정
  으로 이길 때만(P2). Alt=범용 벡터 RAG 기본. Reason=PLAN §1 온디바이스 비판. Trade-off=어휘 밖 유사성 놓칠 수 있음.

## 부록: 검증 (구현 착수 시)
- 실제 코드 인용의 파일·행이 착수 시점과 일치하는지 재확인(이 문서는 조사 시점 스냅샷).
- tool 스키마 프로토타입을 MINTBench로 Qwen3.6 tool-call 정확도 측정(§18 최대 미지수).
- MVP 게이트: 12개 조회 tool로 §Example Traces 1–8·11–12를 E2E 재현.
