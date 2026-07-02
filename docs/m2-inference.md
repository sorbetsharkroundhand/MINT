# M2 — 추론 리스크 선검증 구현 계획

> 브랜치: `claude/macbook-autocomplete-editor-3ejo4p` · 상위 계획: [PLAN.md](../PLAN.md) §6 마일스톤 M2
> ⚠️ 빌드/실행·모델 추론 검증은 **Apple Silicon Mac**에서. (이 개발 환경은 Linux라 컴파일 불가)
> *가장 불확실한 가정(모델 로드·한국어 품질·지연)을 가장 먼저 깬다.*

## 🎯 목표
`Qwen3.6-35B-A3B 4bit`를 로드해 **하드코딩 한국어 이어쓰기 프롬프트**로 생성을 돌리고,
출력·지연을 로그로 확인한다. 한국어 품질·속도를 보고 **기본 모델과 프롬프트 방식
(continuation vs instruct)** 을 확정한다 (PLAN §9-4).

## ✅ 완료 기준 (Definition of Done)
- [ ] 모델이 로드되고 한국어 이어쓰기 출력이 콘솔에 찍힌다
- [ ] 지연 로그 확인: 로드 시간 / 첫 청크 / 전체 / tok/s
- [ ] 첫 제안 지연이 목표(<~300–500ms, PLAN §2) 이내인지 판정
- [ ] continuation vs instruct 품질 비교 → `PromptStyle` 기본값 확정
- [ ] 측정 결과에 따라 기본 모델 확정 (아래 후보 표) → `Settings.swift` 기본값 반영

## 📦 생성/수정 파일
| 파일 | 내용 |
|------|------|
| `Sources/MINTCore/Inference/CompletionEngine.swift` | **신규.** `actor`. 모델 1회 lazy 로드(교체 가능), `complete(prefix:parameters:)` — 취소 가능 스트림 생성, 토큰 상한 + 문장 경계 stop, continuation/instruct 프롬프트 양쪽 지원, 지연 측정치 반환. |
| `Sources/MINTCore/Settings.swift` | **신규.** `CompletionParameters`(엔진 스냅샷) + `CompletionSettings`(UserDefaults, M4 UI 기반) + `ModelPresets`. |
| `Sources/MINTBench/main.swift` | **신규.** M2 벤치 CLI — 로드→생성→지연 로그→판정. `--model/--style/--max-tokens/--runs/--prompt`. |
| `Package.swift` | **수정.** `MLXHuggingFace`(허브 로드 매크로) + `swift-huggingface`/`swift-transformers` + `MLX` 제품 의존 추가, `MINTBench` 타깃 추가. |

## 🔧 핵심 구현 노트
- **로드 경로**: mlx-swift-lm 3.x는 허브 다운로드가 별도 제품으로 분리됨 —
  `#huggingFaceLoadModelContainer(configuration:progressHandler:)` 매크로가
  `HubClient`(swift-huggingface) + `AutoTokenizer`(swift-transformers)로 확장된다.
  ⚠️ 첫 빌드 시 Xcode가 **매크로 신뢰(Trust & Enable)** 를 물으면 허용할 것.
- **취소**: `MLXLMCommon.generate(...) -> AsyncStream<Generation>` 소비 루프를
  이탈하거나 소비 태스크가 취소되면 `onTermination`이 내부 생성 태스크를 취소한다
  (핀 리비전 `Evaluate.swift`에서 확인). M3의 "새 입력 시 in-flight 취소"가 이 위에 선다.
- **continuation 프롬프트**: 챗 템플릿을 우회하기 위해 `tokenizer.encode(text:)` →
  `LMInput(tokens: MLXArray(...))` 로 직접 만든다. instruct는 `UserInput(chat:)` +
  `additionalContext: ["enable_thinking": false]` (Qwen3 계열 사고 모드 차단).

## 🧪 검증 절차 (네 Mac)
```bash
git fetch origin && git checkout claude/macbook-autocomplete-editor-3ejo4p
swift run -c release MINTBench                 # 기본: PLAN 모델 · both 스타일 · 2회
# 모델/설정 바꿔 재측정:
swift run -c release MINTBench --model mlx-community/Qwen2.5-3B-Instruct-4bit
swift run -c release MINTBench --style continuation --max-tokens 8 --runs 3
```
- 첫 실행은 모델 다운로드(수 GB~20GB)로 오래 걸린다. 캐시 후 재실행 기준으로 판정.
- `-c release` 필수 — debug 빌드는 MLX 성능이 크게 떨어진다.

### 기록표 (Mac에서 채우기)
| 모델 | 스타일 | 로드(s) | 첫청크(s) | 전체(s) | tok/s | 한국어 품질 메모 |
|------|--------|---------|-----------|---------|-------|------------------|
| Qwen3.6-35B-A3B-4bit | continuation | | | | | |
| Qwen3.6-35B-A3B-4bit | instruct | | | | | |
| (대안) Qwen3-30B-A3B-4bit | | | | | | |
| (대안) Qwen2.5-3B-Instruct-4bit | | | | | | |

## 🧭 결정 사항 / 열린 질문
- **모델 id 미검증**: 기본 `mlx-community/Qwen3.6-35B-A3B-4bit`는 PLAN 확정치지만
  이 환경(Linux, HF 접근 차단)에서 저장소 존재를 확인하지 못했다. 로드 404면
  `--model`로 대안 사용 후 `ModelPresets`/기본값 수정.
- **메모리**: 35B(A3B) 4bit ≈ ~20GB 상주 — 32GB 미만 Mac이면 처음부터
  `Qwen2.5-3B-Instruct-4bit`(~1.9GB)로 측정 권장.
- **판정 후 반영처**: `CompletionParameters` 기본값(modelID·promptStyle·maxTokens)
  + PLAN §3 기본 모델 표기.
