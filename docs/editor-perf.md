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

## 남은 것

- `serialize()`는 여전히 **매 키 입력마다 문서 전체**를 돈다 — 88k자에서 5ms.
  30만 자 장편(PLAN 목표)이면 ~17ms로 다시 예산을 먹는다. 증분 직렬화(편집된
  문단만 재직렬화 + 캐시 splice)가 정공법이고 CLAUDE.md §2-3("증분이 기본")에도
  맞다. 단일 문단 재직렬화는 **0.00ms**로 측정됐다 — 이득은 확실하나
  `BlockTextView`(3천 행) 구조 변경이라 별도 작업으로 분리한다. §16 부채.
- 폰트가 바뀌면 화면이 바뀐다 — 실기기 육안 확인 필요 (본문 명조, 제목 굵게).
