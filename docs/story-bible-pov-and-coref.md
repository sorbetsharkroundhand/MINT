# 스토리 바이블 성능 개선 — 전역 서술 시점 판별 · 한국어 인물명 정규화

> 설계 문서 (2026-07-21). PLAN §7(캐릭터 시스템)·§6.5–§6.6(Narrative
> Intelligence/Graph)·§14 M11의 후속. 두 개의 구체적 실패를 뿌리부터 고친다.

## 0. 요약

현재 스토리 바이블은 두 가지 실패를 보인다.

1. **전역 서술 시점을 모른다.** 작품이 1인칭인지 3인칭 전지적인지 판별하는
   결정적 장치가 없다. `pov`는 씬/구간 단위 LLM 자유 문자열(`시점=남편`)일
   뿐이고, 시간 이동 구간이 없는 평범한 씬에는 아예 채워지지 않는다
   (`SegmentAnalysis`는 회상·꿈 후보가 있을 때만 호출). 화자(narrator)를
   묻는 질의에 답할 근거 자체가 없다.
2. **인물명 정규화가 파이프라인마다 다르다.** `CharacterDetector`는 조사·매개
   "이"를 벗겨 어간을 잡지만(`CharacterDetector.parse`), **Agent 조회 경로
   (`AgentContext.characterMatches`)는 순수 문자열 비교**라 "점순이"로 물으면
   등록 카드 "점순"을 못 찾거나 별개 인물로 취급한다. 같은 언어 지식이 한 곳에
   모여 있지 않은 게 근본 원인이다.

두 문제 모두 **결정적 로직으로 풀 수 있고**(CLAUDE.md §2-5), **백그라운드에서
준비**되며(§2-2), **증분 갱신**이 가능하고, **MINTBench로 측정**되며, 실패해도
**파생 캐시만 버리면 원문이 안전**하다 — §5 체크리스트 5문항 전부 "예".

---

## 1. 인터넷 조사 — 근거

### 1.1 서술 시점은 대명사 빈도만으로 높은 정확도로 분류된다

Eisenberg & Finlayson, *Automatic Identification of Narrative Diegesis and Point
of View* (CNS 2016). 핵심 결론:

- **최고 성능 특징 집합 = 1·2·3인칭 대명사의 단순 빈도 카운트.** 무거운 구문
  분석·임베딩 없이 대명사 개수만으로 분류기가 선다.
- 결과: 1인칭 POV **F1 0.859**, 3인칭 POV **F1 0.954**, 가중 평균 **0.928**.
- **Diegesis**(서술자가 이야기 안 인물인가 = homodiegetic vs 밖인가 =
  heterodiegetic)는 **"1인칭 대명사가 동사의 논항(주어·목적어)으로 쓰인 횟수"**
  가 핵심 특징. homodiegetic F1 0.721, heterodiegetic F1 0.947.

시사점: 소설의 **1인칭 ↔ 3인칭 판별은 결정적 통계로 충분**하다. 이것은
CLAUDE.md §2-5(결정적 로직 우선)·§5-1(토큰당 품질)에 정확히 부합한다 — LLM
토큰을 한 개도 안 쓰고 전역 시점을 얻는다.

### 1.2 한국어는 조사 분리가 전처리의 기본, 인물 상호참조는 주소어 문화가 핵심 난점

- Korean NLP 전처리에서 **조사(josa) 분리는 표준 단계**다. 명사에서 문법
  기능형태소(은/는/이/가/을/를/에게…)를 벗겨야 "의미 있는 낱말"이 남는다.
  MeCab-ko 등 형태소 분석기가 이를 수행하지만, 우리는 형태소 분석기를 못 쓰므로
  (Apple `NLTagger` 한국어 품사·개체명 미지원, PLAN §16 Q5) 교착어 구조 지식을
  직접 들고 있다 — 이미 `CharacterLexicon`이 그 지식의 그릇이다.
- KoCoNovel (arXiv:2404.01140, 2024) — 한국어 소설 50편·178K 토큰 인물
  상호참조 데이터셋. **전체 인물 언급의 24%가 수식 없는 단일 보통명사**
  (친족어 13.6%·직함 3.1%). 한국어는 이름 대신 **관계·호칭**으로 인물을
  부르는 문화라 상호참조가 영어보다 어렵다. → 우리가 호칭(`honorifics`)을
  구조 신호에서 제외하되 사용자가 직접 등록하게 한 설계(§7)와 일치.
- 별칭(alias) 링크는 **어휘 패턴 매칭 + 동의어 사전**으로 푼다는 것이 상호참조
  연구의 표준. 우리의 표기 변형 병합(유니언-파인드, 요구사항 §17)이 정확히 이
  접근이다 — 다만 **Agent 조회 경로가 이 정규화를 공유하지 못하는 게 버그**다.

**출처**
- [Automatic Identification of Narrative Diegesis and Point of View (ACL W16-5705)](https://aclanthology.org/W16-5705/)
- [Features for automatic classification of narrative point of view and diegesis (US10191975B1)](https://patents.google.com/patent/US10191975B1/en)
- [KoCoNovel: Annotated Dataset of Character Coreference in Korean Novels (arXiv:2404.01140)](https://arxiv.org/html/2404.01140v2)
- [Heuristic-based Korean Coreference Resolution (ACL Y02-1005)](https://aclanthology.org/Y02-1005.pdf)
- [Why Korean NLP is Nothing Like English — preprocessing guide](https://medium.com/@kkang47140/why-korean-nlp-is-nothing-like-english-a-developers-guide-to-preprocessing-challenges-2e3f467e986c)

---

## 2. 현재 코드 진단

### 2.1 시점 — 전역 판별기가 없다

| 위치 | 현재 동작 | 한계 |
| --- | --- | --- |
| `BackgroundIndexer.Prompts.sceneSystem` | 씬 분석 시 `시점: 시점 인물 이름` 한 줄 요청, 모르면 생략 | 씬마다 **자유 문자열**, 작품 전역 일관성 없음. "3인칭 전지적"/"1인칭" 같은 **모드** 개념 자체가 없음 |
| `SegmentParser` (`SegmentAnalysis.swift`) | `시점`·`화자`·`초점` 파싱 | 시간 이동 **후보가 있는 씬에만** 호출(`TemporalShiftDetector.hasCandidate`) → 평범한 씬엔 시점 데이터 0 |
| `NarrativeGraph.NarrativeSegment.narrator` (L121–123) | `"1인칭 남편"·"3인칭 전지적"` 담을 필드 존재 | **아무도 채우지 않는다** — 전역 서술자 산출 로직 부재 |
| `KnowledgeStore.position(at:).pov` | `segment.pov ?? meta?.pov` 폴백 | 둘 다 비면 `nil`. Agent `get_context_at_cursor`의 `pov`도 대개 `null` |

즉 **작품이 1인칭인지 3인칭인지 판정하는 코드가 어디에도 없다.** 화자를 묻는
Agent 질의·프롬프트 헤더가 참조할 사실이 존재하지 않는다.

### 2.2 인물명 정규화 — 지식이 흩어져 있다

`CharacterDetector.parse` (`CharacterDetector.swift:233–252`)는 조사와 **매개 "이"**
를 벗긴다:

```swift
// "서연이가/서연이는" — 받침 이름 뒤 매개 "이"까지 벗긴다(주격 이 제외).
if role != .subject, stem.count >= minStemLength + 1, stem.hasSuffix("이") {
    stem = String(stem.dropLast())
}
```

그러나 **Agent 조회 경로**(`WritingTools.swift`의 `AgentContext.characterMatches`,
L759–776)는 이 지식을 전혀 쓰지 않는다:

```swift
let exact = cards.filter { card in
    card.name.compare(query, options: .caseInsensitive) == .orderedSame
        || aliases(of: card).contains { ... }
}
if !exact.isEmpty { return exact }
return cards.filter { card in
    card.name.localizedCaseInsensitiveContains(query) || ... // 부분 문자열
}
```

문제 재현: 카드 이름 `점순`, 질의 `점순이`.
- exact: `"점순" == "점순이"` → 실패.
- contains: `"점순".contains("점순이")` → 실패 (질의가 이름보다 길다).
- 결과: **"등록 인물 '점순이'을 찾지 못했어요"** 또는 부분일치가 우연히 걸리면
  엉뚱한 인물. 사용자가 겪은 "점순이라는 인물을 가져온다"가 바로 이 경로다.

역방향(카드 `점순이`, 질의 `점순`)도 `contains`가 우연히 통과하지만, 여러
카드가 `점순`을 포함하면 `uniqueCharacter`가 다중 일치로 실패한다.

**근본 원인**: 조사/매개 "이" 정규화가 `CharacterDetector` 안에 사유화돼 있어
Agent·별칭 병합·존대 매트릭스 등 다른 소비자가 공유하지 못한다.

---

## 3. 설계

두 축 모두 **하나의 언어 지식 지점**을 추가하고, 그 지식을 여러 소비자가
공유하게 만든다. 새 저장 스키마는 최소화(파생 캐시)하고, 사용자 데이터는
안 건드린다.

### 3.1 축 A — 전역 서술 시점 판별기 `NarrationMode`

**결정적 · 백그라운드 · 증분 · 측정 가능.** LLM 0회.

#### 3.1.1 도메인 타입

```swift
// Sources/MINTCore/Knowledge/NarrationMode.swift (신규)

/// 작품 전역 서술 시점 — 대명사 빈도 통계에서 결정적으로 파생 (Eisenberg &
/// Finlayson 2016: 대명사 카운트만으로 POV F1 0.928). 파생 캐시라 저장하지 않고
/// KnowledgeSnapshot 조립 시 계산 → 프롬프트 헤더·Agent 조회가 소비한다.
public enum NarrationMode: String, Codable, Sendable, CaseIterable {
    case firstPerson = "1인칭"        // 서술자가 이야기 안 인물 (homodiegetic)
    case thirdPerson = "3인칭"        // 서술자가 이야기 밖 (heterodiegetic)
    case mixed = "혼합"               // 장/구간마다 시점이 갈림 (서간체·다중 화자)
    case unknown = "미상"             // 근거 부족 — 침묵 (품질 > 적극성)
}

public struct NarrationProfile: Codable, Equatable, Sendable {
    public var mode: NarrationMode
    /// 1인칭일 때 서술자 인물 (등록 카드와 이어지면 그 이름, 아니면 nil).
    public var narratorName: String?
    /// 3인칭 전지/제한 구분 — 서로 다른 인물의 내면이 몇 명 서술되는가로 근사.
    /// 2명↑ → 전지적 근사. 1명 → 제한적 근사. 판정 못 하면 nil.
    public var omniscientHint: Bool?
    /// 근거 수치 (설명 UI·벤치 리포트). 서술문(대화 제외) 기준.
    public var firstPersonSubjectHits: Int
    public var thirdPersonProperNameSubjectHits: Int
    public var narrationSentenceCount: Int
}
```

#### 3.1.2 결정적 판정 알고리즘

입력: 원문 + `DocumentOutline`(씬) + `DialogueAttribution` 발화 범위(대화 제외에
필요) + 등록 인물.

1. **서술문만 남긴다.** 큰따옴표·대사 블록(이미 `DialogueAttribution`이 위치를
   안다)을 제외한 **서술 텍스트**에서만 센다. 1인칭 판정을 대사가 오염시키면
   안 된다("나는"은 대사 안에선 아무 인물이나 쓴다).
2. **1인칭 서술자 신호** — 서술문에서 1인칭 대명사가 **문장 주어/주제**로
   나온 횟수:
   - 어간 `나`·`내`·`저(자기 지칭)`·`제`에 주격/주제 조사가 붙은 형태:
     `나는·내가·나도·난·저는·제가`. (지시사 "저 사람"의 "저"는 조사가 안 붙으므로
     구조적으로 배제 — CharacterDetector와 같은 교착어 관문.)
   - `우리`는 1인칭이지만 서술자 단수 지표로 약해 별도 가중(0.5).
3. **3인칭 신호** — 서술문에서 **등록 인물명 또는 `그/그녀`**가 주어/주제로 나온
   횟수.
4. **판정**(문장 정규화된 비율, 임계는 벤치로 보정):
   - `firstPersonSubjectHits / narrationSentenceCount ≥ τ₁`(초안 0.15) **그리고**
     3인칭 인물 주어가 거의 없음 → `firstPerson`.
   - 1인칭 서술 주어가 희박 **그리고** 인물명/그·그녀 주어가 우세 → `thirdPerson`.
   - 장·챕터별로 판정이 엇갈리면 → `mixed`(서간체·1인칭 다중 화자 대응).
   - 어느 쪽도 임계 미달 → `unknown`(짧은 원고·근거 부족 시 **침묵**).
5. **전지/제한 근사**(`omniscientHint`): `SceneInsights`의 앎 델타 또는 서술문
   내면 서술("~라고 생각했다"의 주체)이 **서로 다른 인물 2명 이상**이면 전지적
   근사. 확신 없으면 `nil` — 이 값은 힌트일 뿐 확정이 아니다.
6. **1인칭 서술자 이름 매핑**: 1인칭이면서 대사에서 다른 인물들이 특정 이름으로
   그 서술자를 부르면(호명·귀속) 그 이름을 `narratorName`으로. 못 잡으면 `nil`
   (프롬프트엔 "1인칭 서술자"로만 표기).

#### 3.1.3 자리와 증분

- **자리**: `Sources/MINTCore/Knowledge/NarrationMode.swift` (결정적 판정 enum).
  Knowledge/에 둔다(CLAUDE.md §4 "지식 로직의 자리").
- **계산 시점**: `KnowledgeStore`/`KnowledgeSnapshot` 조립 마지막 단계에서 파생
  (`branches`·`flows`처럼 **저장하지 않는 파생값**). 원문 해시가 안 바뀌면
  재계산 안 함(콘텐츠 해시 메모, §4 백그라운드 3요건).
- **증분**: 서술문 카운트는 씬 단위 누적이라 더티 씬만 다시 세고 전역 합에
  반영한다. 전체 재스캔은 복구 경로.

#### 3.1.4 소비자

- **프롬프트 A 헤더**(`ContextAssembler`): `[서술] 3인칭 전지적` / `[서술] 1인칭
  (서술자: 서연)` 한 줄. 예측이 시점을 어기지 않게(1인칭 원고에서 3인칭 서술
  생성 방지) — 일관성 > 유창성(CLAUDE.md §3).
- **Agent 도구**: `get_active_document` 응답에 `narration_mode`·`narrator` 추가.
  `get_context_at_cursor`의 `pov`가 `null`일 때 전역 `NarrationProfile`로 폴백.
  → 화자 질의에 답할 사실이 생긴다.
- **사용자 오버라이드**: `NarrativeOverride.Kind`에 `.narrationMode` 추가 —
  작가가 "이건 1인칭이야"로 못 박으면 자동 판정을 이긴다(§1-5). 오버라이드는
  entries.json에 살고 재분석이 못 덮는다.

### 3.2 축 B — 공유 한국어 인물명 정규화 `KoreanName`

**한 곳에 언어 지식을 모으고 모든 소비자가 공유한다.**

#### 3.2.1 신규 유틸

```swift
// Sources/MINTCore/Knowledge/KoreanName.swift (신규)

/// 한국어 인물명 정규화 — 조사·매개 "이"를 벗겨 표기를 표준형으로 접는다.
/// CharacterDetector·Agent 조회·별칭 병합이 **같은 규칙**을 쓰게 하는 단일 지점
/// (버그의 근본: 이 지식이 CharacterDetector에 사유화돼 있었다).
public enum KoreanName {

    /// 마지막 음절에 받침이 있는가 — 매개 "이" 삽입 조건 (점순→점순이 O, 영수→영수아 X).
    static func hasFinalConsonant(_ syllable: Character) -> Bool {
        guard let scalar = syllable.unicodeScalars.first,
            (0xAC00...0xD7A3).contains(scalar.value) else { return false }
        return (scalar.value - 0xAC00) % 28 != 0
    }

    /// 이름 표면형에서 뽑을 수 있는 정규화 후보들 (긴 것부터). 질의·카드 양쪽을
    /// 이 집합으로 펼쳐 교집합이 있으면 동일인이다.
    /// - "점순이" → ["점순이", "점순"]   (받침 "순" 뒤 매개 이 제거)
    /// - "서연이가" → ["서연", ...]       (조사 가 + 매개 이 제거)
    /// - "민준" → ["민준"]
    public static func canonicalForms(_ surface: String) -> Set<String> {
        // 1) CharacterLexicon.particles로 최장 조사 1개 제거 (기존 parse 규칙 재사용)
        // 2) 남은 어간이 2음절↑ && 받침 음절 뒤 "이"로 끝나면 그 "이" 제거형도 추가
        // 3) 순수 한글 2~4자 형태만 유효 (isNameShape)
        ...
    }

    /// 두 표면형이 같은 인물을 가리킬 수 있는가 — canonicalForms 교집합.
    public static func mayReferToSame(_ a: String, _ b: String) -> Bool {
        !canonicalForms(a).isDisjoint(with: canonicalForms(b))
    }
}
```

> ⚠️ **모호성 방어**: `순이`·`영이`처럼 "이"로 끝나는 것이 본명일 수 있다.
> 그래서 `canonicalForms`는 원형을 **버리지 않고 함께** 남긴다(집합 반환). 매칭은
> "이 벗긴 형이 등록 카드와 일치하면 동일인"이라는 **한 방향 확장**이라, 카드에
> `순이`가 등록돼 있으면 원형이 그대로 일치해 오작동하지 않는다.

#### 3.2.2 소비자 리팩터

1. **`AgentContext.characterMatches`** (버그 지점, `WritingTools.swift:759`):
   exact 비교 뒤, 실패 시 `KoreanName.mayReferToSame(query, card.name)` **및
   별칭**으로 재시도. 부분 문자열(`localizedCaseInsensitiveContains`) 폴백은
   정규화 일치가 없을 때만, 그리고 **여러 개면 다중 일치로 명확히 실패**시켜
   엉뚱한 인물을 조용히 반환하지 않게 한다.
2. **`CharacterDetector.parse`** (L243–245): 인라인 "이" 제거를 `KoreanName`
   호출로 대체 — 로직 중복 제거, 규칙이 한 곳에서 바뀐다.
3. **`CharacterDetector.isAliasShape`** (L193): 매개 "이" 관계 판정을 `KoreanName`
   기준으로 정렬 — 병합·Agent·감지가 완전히 같은 동일인 규칙을 쓴다.

#### 3.2.3 왜 이게 옳은가

- KoCoNovel·상호참조 연구의 표준(어휘 패턴 + 사전)과 정합. 우리 "사전"은
  등록 카드(사용자 소유 기억, §1-5)다 — 자동 병합이 아니라 **등록된 이름으로만
  확장**하므로 안전하다.
- 조사 스트리핑은 한국어 전처리의 기본. 이미 부분 구현돼 있던 걸 **공유
  가능하게 승격**하는 것이라 리스크가 낮다.

---

## 4. 구현 계획 (단기 브랜치)

트렁크 기반, `feat/` 단기 브랜치. 각 P는 독립 머지 가능.

- **P1 — `KoreanName` 정규화 + Agent 버그 수정** (작은 것 먼저, 즉효)
  - [x] `KoreanName.swift` 신규 (`canonicalForms`·`mayReferToSame`·받침 판정).
  - [x] `characterMatches` 정규화 매칭 + 다중일치 안전 실패.
  - [x] `CharacterDetector.parse`/`isAliasShape` 를 `KoreanName`으로 위임(중복 제거).
  - [x] 결정적 회귀 테스트: (점순↔점순이)·(서연이가→서연)·(순이 본명 오작동 없음)·
        (동음 다중일치 실패) 최소 8건.
- **P2 — `NarrationMode` 전역 판별기**
  - [x] `NarrationMode.swift` 판정 알고리즘(서술문 필터 + 대명사/인물 주어 카운트).
  - [x] `KnowledgeSnapshot` 조립에 `NarrationProfile` 파생(저장 안 함, 메모).
  - [x] `ContextAssembler` 프롬프트 A 헤더 한 줄 + `get_active_document`/
        `get_context_at_cursor` 노출.
  - [x] `NarrativeOverride.Kind.narrationMode` + 바이블/NarrativeView 표시·수정 UI.
  - [x] 결정적 회귀 테스트: 1인칭 픽스처·3인칭 픽스처·서간체(mixed)·짧은 원고
        (unknown) 판정.
- **P3 — 측정 & 문서 동기화**
  - [x] MINTBench: POV 라벨 코퍼스(1인칭/3인칭 각 5편↑) 정확도, 인물 정규화
        일치율(점순류 케이스), 지연 무회귀.
  - [x] PLAN §7·§14 갱신(이 문서 링크), CLAUDE.md 불변식 영향 없음 확인.

구현 측정(2026-07-21, debug): `swift run MINTBench --story-bible-bench`에서
POV 10/10(1인칭·3인칭 각 5편), 이름 정규화 9/9, POV 10편 합계 약 2.5ms.
전체 `swift test`는 실패 0(1개 로컬 픽스처 부재로 건너뜀), M12 집중 회귀는
18개 모두 통과했다.

---

## 5. 측정 (CLAUDE.md §2-7 · §6)

- **POV 정확도**: 라벨된 소설 도막(1인칭·3인칭·서간체)에 대해 `NarrationMode`
  판정 정확도. 목표: 1인칭/3인칭 각 ≥ 0.9 (연구 F1 0.928 기준).
- **인물 정규화 일치율**: (조사·매개이 변형 질의 → 정답 카드) 재현율. 버그 케이스
  "점순이→점순" 포함 골드 세트에서 100%, 오탐(순이 본명 등) 0.
- **지연 무회귀**: 두 판별기 모두 백그라운드/조립 경로 — 예측 첫 고스트 지연
  예산(PLAN §10) 무영향임을 벤치로 확인.
- **E2E**: 1인칭 원고를 열고 예측 시 3인칭 서술이 새지 않는지, Agent에 "이 소설
  화자가 누구야"·"점순이 성격 알려줘"가 올바로 답하는지 실행 확인(§6).

## 6. §5 체크리스트 통과

| 질문 | 답 |
| --- | --- |
| 1. 예측 품질/토큰당 품질이 측정 가능하게 오르는가 | 예 — 시점 일관성·인물 해석 정확도, LLM 0토큰 |
| 2. 백그라운드로 가는가 | 예 — 조립/인덱싱 경로, 예측 시점 아님 |
| 3. 증분 갱신 가능한가 | 예 — 씬 단위 카운트 누적·콘텐츠 해시 메모 |
| 4. 측정 가능한가 | 예 — MINTBench POV 정확도·정규화 일치율 |
| 5. 실패해도 원문 안전한가 | 예 — 둘 다 파생 캐시, 사용자 오버라이드는 entries.json |
