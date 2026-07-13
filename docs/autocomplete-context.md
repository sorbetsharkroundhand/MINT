# 자동완성 컨텍스트 파이프라인 분석

> 상위 계획: [PLAN.md](../PLAN.md) §4·§5 · 관련: [m3-ghost-text.md](m3-ghost-text.md)
> 코드 기준: 2026-07 (사이드바 DnD·폴더 명명 도입 시점). 파일·행 참조는 그 시점 스냅샷.

현재 자동완성이 **모델에 보내는 입력이 정확히 무엇인지**, 어떤 경로로 만들어지는지,
그리고 장문(소설) 글쓰기에서 어디가 약한지를 기록한다.

## 실행 흐름 (7단계)

```
[1] 키 입력 ──▶ [2] NSTextViewDelegate.textDidChange
                     │  BlockTextView.Coordinator.forwardEditEvent
                     │  · prefix 추출: 문서 시작~커서 중 마지막 contextCharacters(기본 1200자)
                     │  · 블록 게이트: 코드·수식·구분선·이미지 블록에선 트리거 안 함
                     ▼
[3] CompletionController.noteEdit  ── 게이트 순서 ──
    retain-word 쇼트컷 → invalidate(기존 고스트 폐기+취소) → 마스터 스위치
    → IME 조합(hasMarkedText) → 문단 끝 → 실패 모델 스로틀 → 2자 이상
    → 디바운스(기본 350ms) 예약
                     ▼
[4] CompletionEngine.complete (actor) — 프롬프트 구성
    · continuation(기본): prefix를 챗 템플릿 없이 그대로 토크나이즈 → LMInput
    · instruct: 한국어 시스템 프롬프트 + 사용자 메시지, enable_thinking=false
                     ▼
[5] MLXLMCommon.generate 스트림 — maxTokens 12 · temperature 0.3 · topP 0.9(하드코딩)
    문장 경계(.!?…。！？\n)에서 조기 종료 · Task 취소에 협조
                     ▼
[6] 후처리 — instruct면 <think>·따옴표 제거 → 공통: 첫 줄바꿈에서 절단, 끝 공백 정리
    stale 검사(세대 카운터) 통과 시 suggestion 발행
                     ▼
[7] suggestionDidChange 클로저 → BlockTextView.ghostText → draw()가 커서 옆
    회색 오버레이로 렌더(0.15s 페이드 인). Tab/→/Esc가 수락·부분 수락·폐기.
```

## 세부 사실

| 질문 | 답 |
|------|----|
| 요청 발원지 | `BlockTextView.Coordinator.textDidChange` → `forwardEditEvent` |
| 컨텍스트 수집 | `storage.substring(to: caret).suffix(contextCharacters)` — **커서 앞 1200자 창** (BlockTextView `prefix(of:before:limit:)`) |
| 문서 범위 | 현재 문서만. 문단 경계를 넘어 이어지지만 커서 **뒤** 텍스트는 안 씀 |
| 시스템 프롬프트 | continuation: **없음** (템플릿 자체를 우회). instruct: `Prompting.instructSystem` ("너는 글쓰기 자동완성 엔진이다…") |
| 편집 이력/대화 이력 | **없음** — 매 요청이 무상태 |
| 토큰 관리 | 입력: 문자 수 clamp(1200자)만, 토큰 기준 아님. 출력: maxTokens 12 + 문장 경계 조기 종료 |
| KV/프롬프트 캐시 | **재사용 없음** — 모델 가중치만 상주, 매 요청 프리필 전체 재계산 |
| 취소 | 세대 카운터(stale 응답 폐기) + `Task.isCancelled` 협조 취소(스트림 종료가 내부 태스크 취소) |
| LLM에 최종 전달 | continuation이면 **1200자 prefix 그대로**가 전부. instruct면 시스템+"다음 글에 바로 이어질 내용을 짧게 이어써라.\n\n{prefix}" |

## 평가 — 약점·병목

1. **후방 컨텍스트 1200자뿐.** 장편(소설)에서 등장인물 이름·설정이 창 밖으로
   밀려나면 모델이 모른다. 짧은 저널엔 충분하지만 소설 모드의 상한으로는 좁다.
2. **문서 메타데이터 미활용.** 제목·종류(journal/novel)·폴더명이 프롬프트에 없다 —
   "소설을 쓰는 중"이라는 신호조차 모델에 전달되지 않는다.
3. **KV 캐시 미재사용이 최대 지연 병목.** 타이핑은 대부분 prefix 뒤에 몇 글자
   붙는 형태라 프리필의 대부분이 직전 요청과 동일한데 매번 전체 재계산한다.
   컨텍스트를 늘릴수록(1번 개선) 이 비용이 선형으로 커져 서로 얽힌 문제다.
4. **커서 뒤 텍스트 무시.** 문단 중간 편집은 "문단 끝" 게이트로 아예 차단되지만,
   FIM(fill-in-middle)이 가능해지면 문단 중간 제안도 열 수 있다.
5. **topP 하드코딩(0.9).** `CompletionParameters`에 없어 벤치로 튜닝 불가.
6. **문자 수 기준 clamp.** 한글은 문자당 토큰 밀도가 높아 1200자는 모델별로
   실제 토큰 수가 크게 다르다 — 토큰 기준 예산이 정확하다.

## 개선 제안 (소설 장문 품질 우선순위 순)

1. **종류·제목 주입**: instruct 프롬프트(또는 continuation 앞 헤더 한 줄)에
   `제목·종류(소설/저널)`를 넣는다. 비용 몇 토큰으로 톤 일관성이 크게 좋아진다.
   `JournalEntry.kind`가 이미 있어 배선만 하면 된다 (PLAN §9 소설 모드의 첫 단추).
2. **KV/프롬프트 캐시 재사용** (PLAN M4 잔여): 직전 요청 prefix와의 공통 앞부분을
   프리필 캐시로 재사용. 이게 되면 3번과 함께 컨텍스트 확대의 지연 비용이 사라진다.
3. **소설 모드 컨텍스트 확대**: kind==novel일 때 contextCharacters를 별도 상한
   (예: 4000자)으로. 2번 없이 올리면 nano에서도 프리필 지연이 눈에 띄니 순서 주의.
4. **요약 헤더(장기 컨텍스트)**: 문서 앞부분(창 밖으로 밀린 부분)을 백그라운드에서
   1~2문장으로 요약해 프롬프트 머리에 붙인다 — 등장인물·설정 유지. 폴더 명명에
   쓴 one-shot instruct 경로(`generateFolderName`)와 같은 패턴으로 구현 가능.
5. **topP를 CompletionParameters로 승격** + MINTBench에 노출 — 측정으로 확정.
6. **토큰 기준 예산**: 토크나이저로 prefix를 자르고, 모델별 컨텍스트 창에 맞춘다.
