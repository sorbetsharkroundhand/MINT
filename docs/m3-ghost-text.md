# M3 — 고스트 텍스트 자동완성 구현 계획

> 브랜치: `claude/macbook-autocomplete-editor-3ejo4p` · 상위 계획: [PLAN.md](../PLAN.md) §4·§5·§9 · 마일스톤 M3
> ⚠️ 빌드/실행·모델 추론 검증은 **Apple Silicon Mac의 Xcode**에서. (이 개발 환경은 Linux)
> 🔗 선행: **M2(추론 리스크 선검증)** — 코드가 함께 구현되어 M2 측정과 M3 검증을 같은
> 브랜치에서 진행한다. 프롬프트 방식(continuation/instruct)과 모델은 M2 벤치 결과로 확정하되,
> 확정 전에도 Settings(⌘,)에서 즉시 바꿀 수 있다.
>
> **상태: 코드 구현 완료 (2026-07) — 아래 DoD는 Mac에서 검증 후 체크.**

## 🎯 목표
M1 에디터에 **Copilot식 인라인 고스트 텍스트 자동완성**을 얹는다:
입력이 멈추면(디바운스) 커서 앞 문맥으로 다음 **단어/구**를 로컬 생성해 **회색 고스트**로 보여주고,
`Tab` 수락 / `Esc`·계속입력 시 폐기 + in-flight 취소. **한글 IME 조합 중에는 트리거하지 않는다.**

## ✅ 완료 기준 (Definition of Done) — PLAN §10 End-to-End
- [ ] 한국어 입력 후 멈춤 → 회색 제안이 **~500ms 내** 등장
- [ ] **조합 중(예: ㅎ→하→한)에는 제안이 뜨지 않음** (`hasMarkedText()` 게이트)
- [ ] `Tab` → 제안이 본문에 커밋, 커서가 뒤로 이동
- [ ] `Esc` 또는 계속 입력 → 고스트 폐기 + 진행 중 생성 취소
- [ ] 고스트는 커밋 전까지 본문·저장(`journal.md`)에 반영되지 않음
- [ ] Mac 검증 통과

## 🏗️ 아키텍처 (PLAN §4·§5 구현)
```
MintTextView(NSTextView) ──텍스트/커서/markedText──▶ CompletionController
        ▲                                                │ 프롬프트(취소 가능)
        │ 회색 고스트 렌더 / Tab·Esc                       ▼
        └───────────── 제안 문자열 ◀────────── CompletionEngine(MLX)
```

## 📦 생성/수정 파일
| 파일 | 내용 |
|------|------|
| `Sources/MINTCore/Inference/CompletionEngine.swift` | **신규.** `actor`. `MLXLLM`/`MLXLMCommon`로 모델 **1회 로드**(lazy), `complete(prefix:) async throws -> String` — 이어쓰기 프롬프트 구성 + **취소 가능** 생성, 토큰 상한(~8–16)·sentence boundary stop. M2에서 검증한 프롬프트 방식 채택. |
| `Sources/MINTCore/Editor/CompletionController.swift` | **신규.** `@MainActor ObservableObject`. 디바운스(입력 멈춤 감지), **IME 게이트**, 커서 앞 컨텍스트 추출, `CompletionEngine` 호출, `suggestion` 상태 발행, `accept()`/`dismiss()`/새 입력 시 in-flight 취소. |
| `Sources/MINTCore/Editor/MintTextView.swift` | **수정.** ① `markedText`/커서 위치 노출(Coordinator에서 `hasMarkedText()`), ② 회색 고스트 렌더(고스트 뒤 임시 attributed substring 또는 layoutManager), ③ `Tab`=수락·`Esc`=거부 키 처리(`doCommandBy` / keyDown 가로채기), ④ 편집 발생 시 고스트 즉시 제거. |
| `Sources/MINTCore/ContentView.swift` | **수정.** `@StateObject CompletionController` 배선, `MintTextView`에 controller 연결, `DocumentStore`와 공존(고스트는 저장 대상 아님), 하단 엔진 상태 바. |
| `Sources/MINTCore/Settings.swift` | **신규.** `CompletionSettings`(UserDefaults) + `CompletionParameters`(엔진 스냅샷) + `ModelPresets` — 디바운스·토큰 수·모델 id·프롬프트 방식. |
| `Sources/MINTCore/SettingsView.swift` | **신규(M4 선반영).** ⌘, 설정 화면 — 모델·프롬프트 방식·디바운스·토큰·온도. |

## ♻️ 재사용 (기존 코드)
- **디바운스 + Task 취소 패턴**: `DocumentStore.scheduleSave()`
  (`Sources/MINTCore/Storage/DocumentStore.swift`) — 이전 `Task` 취소 후 `Task.sleep`으로 재예약하는
  구조를 `CompletionController`의 트리거 디바운스에 그대로 차용.
- **NSTextViewDelegate 훅**: `MintTextView.Coordinator.textDidChange`
  (`Sources/MINTCore/Editor/MintTextView.swift`) — 여기에 IME 게이트·트리거 호출을 얹는다.
  파일에 이미 남겨둔 M3 확장 지점 주석 참조.

## 🔧 핵심 기술 대응 (PLAN §9)
1. **IME + 고스트**: `textView.hasMarkedText()`가 true면 트리거 skip. 조합 커밋 & 입력 멈춤일 때만 발화.
2. **지연시간**: 4-bit 모델 상주, 토큰 상한(~8–16), 문장경계 stop, 새 키 입력 시 즉시 `Task` 취소.
   ⚠️ 35B(A3B) 모델이라 로드·첫 토큰 지연이 클 수 있음 → M2 측정 결과에 따라 상한/모델 재조정.
3. **고스트 렌더**: 비영속 회색 attributed 텍스트로 커서 뒤에 표시, `Tab` 전엔 본문 미반영.
4. **프롬프트**: instruct + 간결 시스템("이어질 내용을 자연스럽게 짧게 이어써") vs 순수 continuation
   — M2 실험 결론 반영.

## 🧪 검증 절차 (네 Mac)
```bash
git fetch origin && git checkout claude/macbook-autocomplete-editor-3ejo4p
open Package.swift        # Xcode → MINT 스킴 → ⌘R
```
- 의존성이 바뀌었으므로 첫 열기에서 패키지 재해석(네트워크 필요) + **매크로
  신뢰(Trust & Enable)** 확인이 뜨면 허용.
- 첫 실행은 하단 상태 바에 모델 다운로드 진행률이 표시된다(기본 모델 ~20GB —
  메모리/디스크가 부담이면 ⌘,에서 `Qwen2.5-3B-Instruct-4bit`로 교체 후 "다시 시도").

1. 한국어 문장 입력 후 멈춤 → 회색 제안 ~500ms 내 등장 (상태 바 "준비됨" 이후).
2. 조합 중(자모 입력 중)에는 제안 **미등장** 확인.
3. `Tab` 삽입 / `Esc` 폐기 / 계속 입력 시 취소 / 커서 이동 시 폐기 확인.
4. 종료·재실행 → `journal.md`에 고스트가 아닌 **확정 본문만** 보존.

## 🧭 결정 사항 / 열린 질문
- **고스트 렌더 방식 (확정)**: 임시 attributed substring도 layoutManager 개입도 아닌
  **`draw(_:)` 오버레이 그리기**를 채택 — `GhostTextView.draw`가 커서 사각형
  (`firstRect(forCharacterRange:)`, IME 후보창과 같은 경로)을 얻어 그 뒤에 회색으로 그린다.
  text storage가 오염되지 않아 커서·undo·autosave·바인딩이 자동으로 안전해진다.
- **트리거 위치 (확정)**: 커서 뒤~문단 끝에 내용이 있으면 트리거하지 않는다
  (`isCaretAtParagraphEnd`). 고스트를 본문과 겹쳐 그리는 문제를 원천 차단하는 MVP 단순화 —
  저널 입력은 대부분 문단 끝에서 일어난다. 문단 중간 제안은 이후 확장.
- **커서 이동 = 폐기 (확정)**: 제안 발행 시 커서 위치를 앵커로 기억하고
  (`suggestionAnchor`), 커서가 벗어나면 즉시 폐기한다. 드래그 선택도 폐기.
- **Esc 가로채기 (확정)**: `cancelOperation:`과 `complete:`(NSTextView 기본 완성 팝업 경로)
  둘 다 delegate `doCommandBy`에서 가로챈다.
- **모델 크기 vs 지연 목표 (열림)**: §2 목표는 첫 제안 <~300–500ms인데 기본 모델이 35B(A3B)로 커짐.
  M2 측정에서 목표 초과 시 → 상한 축소, 더 작은 대안(`Qwen2.5-3B`) 또는 KV/프롬프트 캐시 재사용 검토.
- **수락 단위 (열림)**: 단어 단위 부분 수락(예: `Tab`=전체, `⌥Tab`=한 단어)은 M4 이후로 미룸.
