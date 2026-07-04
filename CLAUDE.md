# MINT — Claude Code 작업 가이드

한글 온디바이스 자동완성 저널 에디터 (macOS, SwiftUI + AppKit + MLX).
설계·로드맵은 [PLAN.md](PLAN.md), 사용자 안내는 [README.md](README.md).

## 빌드 / 실행 (중요)

- **컴파일 확인**: `swift build` — 타입 체크용으로는 충분하다.
- **실행은 `swift build` 산출물로 하면 크래시** ("Failed to load the default
  metallib") — SwiftPM CLI는 MLX Metal 셰이더를 빌드하지 못한다.
  - 해결: `scripts/prepare-metallib.sh` 1회 실행 (xcodebuild로 metallib 생성·복사)
    → 이후 `swift run MINT` 동작. mlx-swift 버전을 올리면 다시 실행.
- 벤치 CLI: `swift run -c release MINTBench` (동일한 metallib 제약).

## 구조

- `Sources/MINT/` — `@main` 앱 셸 (얇게 유지).
- `Sources/MINTCore/` — 모든 로직·UI. 관심사는 폴더로 분리:
  `Editor/`(블록 에디터·자동완성 컨트롤러) · `Inference/`(MLX 엔진) ·
  `Storage/`(EntryStore) · 루트(뷰·테마·설정).
- `Sources/MINTBench/` — 추론 측정 CLI.

## 컨벤션

- 주석·UI 문자열은 **한국어**. 주석은 "왜"를 적는다 (PLAN 섹션 참조 형식: `PLAN §N`).
- 색·폰트는 반드시 `Theme.swift`의 `MintTheme`/`MintFonts` 토큰을 쓴다
  (라이트/다크 두 벌). 하드코딩 색 금지.
- 토글 UI는 `ContentView.swift`의 `GlassSwitch` 재사용 — 리퀴드 글래스 디테일 통일.
- 설정은 `CompletionSettings`(UserDefaults, `completion.*` 키)에 추가하고,
  추론 쪽엔 `CompletionParameters` 스냅샷만 넘긴다 (actor 격리 경계).
- 자동완성 동작 변경 시 게이트 순서 유지: 마스터 스위치 → IME 조합(`hasMarkedText`)
  → 문단 끝 → 컨텍스트 길이 → 디바운스. 한글 조합 중 트리거는 절대 금지.
- 트렁크 기반: `main`은 항상 빌드되게, 기능은 단기 브랜치(`feat/`·`fix/`·`spike/`) 후 머지.

## 검증

- 변경 후 최소 `swift build` 통과 확인.
- UX 변경은 실행해서 확인: 제안 등장(~500ms) · 조합 중 미등장 · Tab/→/Esc ·
  재실행 시 저널 보존 (`~/Documents/MINT/entries.json`).
