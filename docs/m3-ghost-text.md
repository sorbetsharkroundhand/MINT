# M3 — 고스트 텍스트 자동완성 구현 계획

> 브랜치(예정): `feat/m3-ghost-text` · 상위 계획: [PLAN.md](../PLAN.md) §4·§5·§9 · 마일스톤 M3
> ⚠️ 빌드/실행·모델 추론 검증은 **Apple Silicon Mac의 Xcode**에서. (이 개발 환경은 Linux)
> 🔗 선행: **M2(추론 리스크 선검증)** — 모델 로드·한국어 이어쓰기 품질·지연이 목표 이내임을
> 먼저 확인해야 M3에 착수한다. M2에서 확정한 모델(`Qwen3.6-35B-A3B 4bit`)과 프롬프트 방식을 그대로 사용.

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
| `Sources/MINTCore/ContentView.swift` | **수정.** `@StateObject CompletionController` 배선, `MintTextView`에 controller 연결, `DocumentStore`와 공존(고스트는 저장 대상 아님). |
| `Sources/MINTCore/Settings.swift` | **신규(경량, 선택)** — 디바운스·토큰 수·모델 id. (본격 Settings UI는 M4) |

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
git fetch origin && git checkout feat/m3-ghost-text
open Package.swift        # Xcode → MINT 스킴 → ⌘R
```
1. 한국어 문장 입력 후 멈춤 → 회색 제안 ~500ms 내 등장.
2. 조합 중(자모 입력 중)에는 제안 **미등장** 확인.
3. `Tab` 삽입 / `Esc` 폐기 / 계속 입력 시 취소 확인.
4. 종료·재실행 → `journal.md`에 고스트가 아닌 **확정 본문만** 보존.

## 🧭 결정 사항 / 열린 질문
- **모델 크기 vs 지연 목표**: §2 목표는 첫 제안 <~300–500ms인데 기본 모델이 35B(A3B)로 커짐.
  M2 측정에서 목표 초과 시 → 상한 축소, 더 작은 대안(`Qwen2.5-3B`) 또는 KV/프롬프트 캐시 재사용 검토.
- **고스트 렌더 방식**: 임시 attributed substring(간단) vs layoutManager 직접 그리기(정교) — Mac에서
  커서 거동 확인 후 택1.
- **수락 단위**: 단어 단위 부분 수락(예: `Tab`=전체, `⌥Tab`=한 단어)은 M4로 미룸.
