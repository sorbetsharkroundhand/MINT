# MINT
Mac Intelligent Note Taker — 한글 저널링을 위한 **온디바이스 스마트 자동완성 에디터**.

입력을 멈추면 로컬 LLM(MLX)이 다음 단어/구를 **회색 고스트 텍스트**로 제안한다.
`Tab` 수락 · `Esc` 거부 · 계속 입력하면 자동 폐기. 모든 추론은 완전 로컬 —
일기는 어디에도 전송되지 않는다. 상세 설계는 [PLAN.md](PLAN.md).

## 요구사항
- Apple Silicon Mac (MLX), macOS 14+, Xcode 16+ (Swift 6)
- 첫 실행 시 모델 다운로드 — 기본 모델은 ~20GB. 메모리가 부담이면
  설정(⌘,)에서 `mlx-community/Qwen2.5-3B-Instruct-4bit`(~1.9GB)로 교체.

## 실행
```bash
open Package.swift    # Xcode → MINT 스킴 → ⌘R
```
- 첫 열기에서 패키지 해석 + 매크로 신뢰(Trust & Enable) 확인이 뜨면 허용.
- 본문은 `~/Documents/MINT/journal.md`에 자동 저장된다.

## M2 추론 벤치 (모델·프롬프트 확정용)
```bash
swift run -c release MINTBench            # 기본 모델, continuation/instruct 비교
swift run -c release MINTBench --help     # 옵션
```
측정 절차와 기록표: [docs/m2-inference.md](docs/m2-inference.md)

## 상태
- M0 스캐폴드 ✅ · M1 에디터+저장 ✅
- M2 추론 선검증 🧪 코드 완료 — Mac 측정 대기
- M3 고스트 자동완성 🔨 코드 완료 — Mac E2E 검증 대기 ([docs/m3-ghost-text.md](docs/m3-ghost-text.md))
- M4 다듬기 🔨 부분(설정 UI·상태 바)
