# MLX 생성 취소·조기 종료 안정성 검증 (2026-08-23)

## 환경

- MacBook Pro (Mac14,6), Apple M2 Max 12코어, 메모리 32GB
- macOS 26.6 (25G72), Swift 6.3.3
- `mlx-swift` `dc43e62d7055353c7f99fa071a4e71d29dfddc44`
- `mlx-swift-lm` `1c05248bb0899e2a7a4962b84d319cf12f4e12aa`
- 모델: `mlx-community/Qwen2.5-3B-Instruct-4bit`

## 재현 명령과 결과

릴리즈 빌드:

```bash
swift build -c release
```

내부 token loop 생성 신호 이후 취소와 첫 청크 조기 종료:

```bash
.build/release/MINTBench \
  --model mlx-community/Qwen2.5-3B-Instruct-4bit \
  --cancellation-stress 20
```

- 첫 청크에서 스트림 소비 종료 → 내부 Task `cancelAndWait` → 후속 생성 성공
- 내부 생성 시작 신호 이후 호출자 취소 → 후속 생성 20/20 성공
- 위 명령을 독립 프로세스 10개로 반복: 각 20/20, 총 200/200 성공
- 모든 프로세스 exit 0, EXIT=11과 빈 후속 생성 없음

KV 캐시 회귀:

```bash
.build/release/MINTBench \
  --model mlx-community/Qwen2.5-3B-Instruct-4bit \
  --replay Fixtures/replay-novel-ko-v1.txt \
  --context 1200 --max-tokens 12 --runs 1
```

- 평균 프롬프트 764토큰, 웜 재사용 763토큰
- TTFC 콜드 0.50초 → 웜 0.01초

## 판정

고수준 스트림 소비가 먼저 끝나도 숨은 MLX 생성 Task의 실제 종료를 기다리고,
모델 교체는 기존 컨테이너 사용권이 모두 반환된 뒤 진행한다. 2026-08-22에 기록한
릴리즈 CLI EXIT=11은 이 검증 범위에서 재현되지 않았다. 모델·mlx-swift 버전 변경
때는 metallib을 다시 준비한 뒤 같은 명령을 반복한다.
