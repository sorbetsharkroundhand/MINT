# 모델 라인업 v2 벤치 — 지연·KV 재사용·한국어 품질 (2026-08-22)

PLAN §16-1·§16-2(라인업 v2 미측정 문제)의 첫 실측. 리플레이 벤치
(docs/m5-replay-bench.md 방법론, 컷 12개·maxTokens 12·온도 0.3)으로 세 모델을
같은 절차로 돌렸다.

## 환경·절차

- 기기: Mac14,6 (M2 Max, 32GB)
- 빌드: `swift build -c release` · mlx.metallib 스탬프 일치 확인 후
- 명령: `.build/release/MINTBench --replay Fixtures/replay-novel-ko-v1.txt --context 1200`
  (②번만 `--context 4000 --title "등대지기의 겨울" --genre "가족 드라마"`)
- 모델은 HF 캐시 사용, 로드는 캐시 히트 1–2s.
- 참고: 당시 실행 종료 직후 세그폴트(EXIT=11)가 재현됐다(MINT·Peppermint) — 출력은
  요약까지 정상 완료 후 붕괴라 수치 신뢰에는 영향 없음. 이 수명주기 부채는
  2026-08-23에 해소했다 (`docs/cancellation-stress-2026-08-23.md`).

## 결과

| 모델 | 컨텍스트 | 웜 KV 재사용 | 콜드 → 웜 TTFC | 프록시 적중률(≥2자) | 어절 적중률 |
|------|------|------|------|------|------|
| **MINT** Ternary-Bonsai-27B·2bit 밀집 | 1200 | **0 / 632 tok** | 4.25s → 4.24s | 17% | 8% |
| **Basil** GLM-4.7-Flash 30B·A3B MoE | 1200 | **884 / 885 tok** | 2.34s → **0.05s** | 0% | 25% |
| **Basil** | 4000+헤더 | **2027 / 2028 tok** | 4.92s → **0.06s** | 0% | 17% |
| **Peppermint** Qwen3.6-35B·A3B MoE | 1200 | **0 / 632 tok** | 1.41s → 1.14s | 25% | 8% |

## 결론

1. **§16-1 판정 — MINT를 기본으로 둘 수 없다.**
   - 웜 TTFC 4.24s = 예산(≤400ms Fast·≤500ms Story, PLAN §10)의 ~9배. 웜이 콜드와
     같은 이유는 아래 2번 — KV 전략이 통째로 무효라 매 요청이 전체 프리필이다.
   - 프리필 자체가 느리다: ~136tok 1.16s · ~749tok 5.33s ≈ 6–8ms/tok. 밀집 27B
     2bit + 하이브리드(선형어텐션) 스캔 비용으로 추정.
   - 품질: 사고 태그 오염(아래 4번) 외에도 제안에 중국자 유입("亮히"·"特别히"·
     "灵魂") — 1.71bpw 공격적 양자화가 한국어에서 먼저 무너진다는 §16-1 우려의
     직접 증거. 프록시 적중률 17%도 세 모델 중 최하위권은 아니나 어절 적중률 8%로
     Basil 대비 열세.
2. **KV 재사용은 순수 어텐션 모델에서만 작동한다 (아키텍처 발견).**
   Qwen3.5/3.6 계열은 선형어텐션 레이어에 `MambaCache`를 쓰고(ml mlx-swift-lm
   `Qwen35.newCache`), `ArraysCache.isTrimmable == false` 상속이라
   `canTrimPromptCache`가 false다 → LCP trim 경로(PromptCacheBox.reusableSuffix)가
   항상 폴백. 재사용 0은 우리 코드의 결함이 아니라 구조적 한계 — 폴백 동작이
   정확하다. GLM-4.7-Flash는 trimmable 캐시라 §12 전략이 그대로 유효했다
   (2027/2028 tok 재사용, 웜 0.06s).
3. **§16-2 배치 — Basil이 지연 아키텍처와 맞는 유일한 모델.** 웜 0.05s는 예산의
   1/10. Peppermint는 MoE라 콜드 1.41s로 MINT보다 빠르지만 재사용 불가로 웜 이득이
   없다. 품질 프록시는 세 모델 다 낮아(문장 경계 컷의 한계, docs/m6-knowledge.md)
   어절 적중률(Basil 25%)이 상대 비교에 더 유효했다.
4. **사고 태그 오염 수정**: 사고 학습 모델(Qwen3.5 계열)은 이어쓰기에서도
   `<think>…</think>`·홀로 `</think>`를 내보내 제안이 태그 그 자체였다.
   `CompletionEngine.stripContinuationThinking`으로 접두 태그만 벗긴다(단위
   테스트 6건). 수정 후 같은 벤치 재실행 — 오염 소멸, 품질 지표 동일(17%·8%,
   형식 교정이지 품질 향상이 아니므로 예상대로).
5. **남음**: 4000자 컨텍스트에서의 Peppermint·MINT 측정, 실사용 수락률 로깅과의
   대조(프록시의 한계). 기본 모델 교체 여부는 사용자 결정 —
   데이터상 Basil 기본 전환이 지연·재사용·오염 면에서 근거를 갖는다.
