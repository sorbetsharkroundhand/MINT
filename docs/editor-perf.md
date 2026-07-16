# 에디터 지연 — 장편에서 타이핑이 밀리는 원인 (2026-07-15)

**증상**: 소설이 길어질수록 타이핑에 랙. 「위대한 개츠비」(88,186자)에서 체감.

**결론**: 원인은 에디터 로직이 아니라 **폰트 폴백**이었다. 한글을 못 덮는 폰트를
본문에 깔아 NSTextStorage가 한글마다 폰트 대체 런을 쪼갰고, 매 키 입력마다 도는
`serialize()`가 그 런을 전부 훑고 있었다.

## 측정 (실제 저널, `swiftc -O`)

매 키 입력마다 `BlockTextView.serialize()`가 문서 전체를 직렬화한다
(`Coordinator.textDidChange` → `parent.text = serialized`).

| 본문 폰트 | 속성 런 | serialize() | 한글 커버 |
|---|---|---|---|
| **시스템 serif (당시 폴백)** | **42,678개** | **42–49 ms** | ❌ |
| Nanum Myeongjo | 539개 | **5.05 ms** | ✅ |
| AppleMyungjo | 537개 | 5.53 ms | ✅ |
| Apple SD Gothic Neo | 537개 | 7.77 ms | ✅ |

문단 535개짜리 문서에서 런이 문단당 ~80개로 터졌다 → 문단당 1개로 정상화.
프레임 예산은 16.7ms(60fps) — 43ms는 예산의 2.6배, 5ms는 30%.

### 왜 런이 터지나

`MintFonts.serif()`는 Noto Serif KR이 없으면 `NSFont.systemFont(...).withDesign(.serif)`
(= New York/Times)로 폴백했다. 이 폰트는 한글 글리프가 없다. NSTextStorage는
저장 시 폰트 속성을 고정(attribute fixing)하면서 **글리프가 없는 구간마다 대체
폰트 런을 새로 만든다**. 한글 원고에서는 사실상 텍스트 조각마다 런이 생긴다.

측정 환경에 Noto Serif KR·Pretendard가 **설치돼 있지 않아** 폴백 경로가 상시
동작 중이었다 — 즉 이 사용자에게는 예외가 아니라 기본 경로였다.

### 오해였던 것 (측정으로 기각)

- **저장 경로**: 265KB 전 저널 JSON 인코딩 + 원자적 쓰기 = **1.86ms** (디바운스
  800ms마다 1회). `@MainActor` `Task`라 메인에서 돌지만 프레임 예산의 9%다.
  PLAN §16의 "전 원고 재저장" 부채는 유효하나 **이 랙의 원인은 아니다.**
- **`InlineStyle.serialize`의 `storage.string as NSString` 반복 브리지**: 클로저
  밖으로 호이스팅해도 42.10 → 42.29ms로 **차이 없음**. Foundation이 브리지를
  캐싱한다. O(n²) 가설은 틀렸다.
- serialize() 구간 분해(런 42k 상태): 문단 walk 0.93ms · +enumerateAttributes
  18.79ms · +substring 26.86ms · +문자열 누적 35.96ms · +join 37.71ms.
  비용이 한 곳에 있지 않고 **런 수에 비례해 전 구간에 퍼져 있다** — 런을 줄이는
  것이 유일하게 의미 있는 수정이었다.

## 수정

`Theme.swift`의 폴백 목록에 **한글을 덮는** 폰트를 넣는다. 한국어 앱에서 라틴
전용 폰트 폴백은 금지 — 취향이 아니라 성능 문제다.

- 본문: `Noto Serif KR → NotoSerifKR → Nanum Myeongjo → AppleMyungjo`
  (Nanum Myeongjo는 Bold 보유, AppleMyungjo는 Regular뿐이라 뒤).
- UI: `Pretendard Variable → Pretendard → Apple SD Gothic Neo` (한글 9종 굵기).

둘 다 macOS 한국어 지원에 딸려 오므로 별도 설치가 필요 없다.

---

# 2차 조사 (2026-07-16) — "chapter 분할" 검토와 실제 O(n) 제거

"장문 편집이 느리니 문서를 Chapter로 쪼개 virtualization하자"는 제안을 측정으로
검토했고, **기각했다.** 병목은 레이아웃·렌더링이 아니라 전부 우리 코드였다.

## 레이아웃은 병목이 아니다 (문서 길이와 무관)

실제 `NSTextView` + `NSScrollView`를 창에 올려 키 입력 1회를 쟀다:

| 길이 | `insertText` | `frame` + `usedRect` |
|---|---|---|
| 22,000자 | 0.136 ms | 0.000 ms |
| 88,000자 | 0.925 ms | 0.000 ms |
| 200,000자 | 0.132 ms | 0.000 ms |
| **300,000자** | **0.163 ms** | **0.000 ms** |

**완전히 평평하다.** `allowsNonContiguousLayout` ON/OFF도 차이가 없었다 —
NSLayoutManager는 편집된 문단만 무효화하고 나머지는 라인 프래그먼트 캐시를 쓴다.
TextKit 1은 이미 필요한 만큼만 레이아웃한다. **"긴 문서 = O(n) 레이아웃"은 사실이
아니다.** 따라서 viewport windowing은 이미 얻고 있는 것을 다시 만드는 일이다.

## 진짜 O(n)은 전부 우리 코드였다 (키 입력 1회, 문서 길이별)

| | 22k | 88k | 200k | 300k |
|---|---|---|---|---|
| `refreshRenderedBlocks`의 `range(of:)×2` | 1.24 | 5.00 | 11.25 | **16.91 ms** |
| `drawBackground` 전체 문단 순회 | 0.58 | 1.47 | 3.58 | **5.15 ms** |
| `serialize()` | ~1.5 | ~5 | ~11 | **~17 ms** |
| (참고) TextKit 레이아웃 | 0.14 | 0.93 | 0.13 | **0.16 ms** |

30만 자에서 우리 코드 ~39ms vs TextKit 0.16ms — **240배**.

## 수정 (측정으로 검증)

| 300k자 | 기존 | 수정 후 |
|---|---|---|
| `drawBackground` | 5.135 ms | **0.172 ms** |
| 마커 검사 | 16.605 ms | **0.0012 ms** |

1. **`MintLayoutManager.drawBackground`** — `glyphsToShow`를 인자로 받아놓고
   무시한 채 문서 전체를 돌고 있었다. 보이는 문단만 훑되, 코드 런은 병합
   렌더라 런의 시작·끝까지만 넓힌다(런 길이에 비례, 문서 길이와 무관).
2. **`refreshRenderedBlocks`의 마커 검사** — 매 키 입력마다 `range(of:"$$")`·
   `range(of:"![")`로 문서 전체를 훑었다. `mayHaveMarkers` 캐시 + 편집 범위
   ±1글자만 검사(`NSTextStorageDelegate`)로 대체. **보수적으로 틀린다** —
   확신이 없으면 true로 두어 전체 경로를 타게 하고, 전체 경로가 한 번 돌면
   `syncMarkerFlag()`가 실측으로 되돌린다(삭제로 마커가 사라진 경우의 복귀로).
   정확성 검증 7건: `$$`를 한 글자씩 나눠 입력·붙여넣기·사이에 삽입 모두 감지,
   `$`·`!`·`[` 단독은 오탐 없음(할 일 목록 `- [` 포함).

## chapter 분할을 기각한 이유

- **병목을 못 고친다**: 위 셋은 chapter 안에서도 그 chapter 전체를 돈다. chapter를
  작게 잡아 비용이 주는 건 "범위를 제한하면 빨라진다"는 얘기이고, 그 효과는 각
  함수의 범위를 고쳐 아키텍처 변경 없이 그대로 얻었다(위 표).
- **이미 있는 것의 재구현**: TextKit이 뷰포트 레이아웃을 이미 한다.
- **깨뜨리는 것이 많다**: 여러 NSTextView는 chapter 경계를 넘는 selection·undo·
  copy/paste·전체 검색·방향키 이동을 전부 직접 구현해야 한다 — NSTextView는 자기
  storage 밖의 선택을 모른다. 요구된 "기존 동작 유지"와 정면 충돌.
- 저장 단위 분리(chapter별 파일)는 **별개 사안**이다. 현재 전 저널 재저장은
  1.86ms(디바운스 800ms마다 1회)로 병목이 아니다 — PLAN §16 부채로 유효하나
  입력 지연과는 무관하다.

## 남은 것 — `serialize()`가 유일한 O(n)

두 수정 뒤 30만 자 키 입력 1회의 구성:

| 항목 | 비용 |
|---|---|
| **`serialize()`** | **~17 ms** ← 남은 전부 |
| drawBackground | 0.17 ms |
| 마커 검사 | 0.001 ms |
| TextKit 레이아웃 | 0.16 ms |

`Coordinator.textDidChange`가 매 키 입력마다 문서 전체를 직렬화해
`parent.text`(→ `EntryStore.body`)에 넣는다. 88k자에서 5ms라 지금은 예산 안이지만,
PLAN 목표인 30만 자에서는 이것만으로 예산을 넘는다.

두 가지 안 — **둘 다 원고 유실 위험이 있어 별도 작업으로 분리한다**:

- **(A) 증분 직렬화**: 편집된 문단만 재직렬화해 캐시에 splice. 단일 문단
  재직렬화는 **0.00ms**로 측정됐다. 정공법이고 CLAUDE.md §2-3에 맞다.
  위험: 캐시 버그 = 저장 텍스트 손상 = **원고 손상**. 문단 인덱스가 개행
  삽입·삭제로 밀리므로 splice 로직이 까다롭다. 이제 `NSTextStorageDelegate`가
  있어 편집 범위는 알 수 있다(마커 캐시가 깔아 둔 길).
- **(B) 직렬화 디바운스**: 타이핑이 멈출 때만 직렬화. 키 입력 비용 → 0이고
  변경량이 작다. 위험: ⌘Q·저널 전환이 디바운스 창 안에서 일어나면 마지막
  입력이 유실된다(`EntryStore.flush`가 낡은 `body`를 쓴다). 저널 전환 시
  **이전 저널로** 플러시하는 경로가 반드시 필요하다.

(A)가 옳지만 (B)가 싸다. 어느 쪽이든 "이어붙인 결과 == 원문" 테스트를 먼저
고정하고 착수할 것 — 원고 유실은 되돌릴 수 없다.

## 육안 미확인

- 본문 폰트가 명조체로 바뀐 것 (1차 수정) — 실기기 확인 필요.
- `drawBackground` 범위 제한 후 **코드 블록 배경이 화면 경계에서 잘리지 않는지** —
  런 확장 로직이 맞는지는 코드 블록이 뷰포트보다 긴 문서를 스크롤해 봐야 안다.
