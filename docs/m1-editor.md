# M1 — 에디터 + 저장 구현 계획

> 브랜치: `claude/plan-review-next-steps-dcpojv` · 상위 계획: [PLAN.md](../PLAN.md) §6 마일스톤 M1
> ⚠️ 빌드/실행 검증은 **Apple Silicon Mac의 Xcode**에서. (이 개발 환경은 Linux라 컴파일 불가)

## 🎯 목표
임시 `TextEditor`를 커스텀 **`NSTextView` 래퍼(`MintTextView`)** 로 교체하고,
**`DocumentStore`** 로 `~/Documents/MINT/journal.md`에 디바운스 autosave/load를 붙인다.
"입력 → 저장 → 재실행 → 복원"의 텍스트 왕복을 검증한다.

이 단계에는 자동완성·MLX 추론이 **없다** — 편집 + 로컬 저장의 세로 슬라이스만.

## ✅ 완료 기준 (Definition of Done)
- [ ] 커스텀 에디터에 **한글 타이핑**이 됨 (IME 조합 정상, 커서 안 튐)
- [ ] 입력 멈추면 `~/Documents/MINT/journal.md`에 내용 저장됨
- [ ] 앱 종료 후 재실행 → 이전 텍스트 **복원**
- [ ] `MINTCore`의 SwiftUI 프리뷰 동작
- [ ] Mac 검증 통과

## 📦 생성/수정 파일
| 파일 | 내용 요약 |
|------|-----------|
| `Sources/MINTCore/Editor/MintTextView.swift` | **신규.** `NSViewRepresentable` → `NSScrollView`+`NSTextView`. `@Binding text`, `Coordinator: NSTextViewDelegate`의 `textDidChange`로 바인딩 갱신. 서식·스마트치환 off. M3 확장 지점(고스트/IME 게이트) 주석. |
| `Sources/MINTCore/Storage/DocumentStore.swift` | **신규.** `@MainActor ObservableObject`. `journal.md` 경로/디렉터리 보장, `load()`, `scheduleSave()`가 이전 `Task` 취소 후 ~800ms 디바운스로 atomic write. |
| `Sources/MINTCore/ContentView.swift` | **수정.** `@StateObject DocumentStore` + `MintTextView($store.text)`, placeholder 오버레이 유지, `.onAppear`에서 load, `.onChange(text)`에서 scheduleSave. |

## 🔧 작업 순서
1. ✅ 위 3개 파일 작성
2. ✅ M1 문서 작성 + PLAN 로드맵 M0 완료 표시
3. 커밋: `feat: M1 에디터 + 저장 — NSTextView 래퍼 + journal.md autosave`
4. push → **Mac에서 빌드 검증**

## 🧪 검증 절차 (네 Mac)
```bash
git fetch origin
git checkout claude/plan-review-next-steps-dcpojv
open Package.swift          # Xcode → MINT 스킴 → ⌘R
```
1. 창이 뜨고 한글 타이핑이 됨.
2. 몇 초 멈춘 뒤: `cat ~/Documents/MINT/journal.md` 로 저장 확인.
3. 앱 종료 → 재실행 → 이전 텍스트 복원 확인.

## 🧭 결정 사항 / 열린 질문
- **autosave 디바운스 800ms**: 입력 흐름을 방해하지 않는 선. M4 Settings에서 노출 검토.
- **IME 반영**: M1은 `textDidChange`의 `string`을 그대로 바인딩(조합 결과 포함). 조합 중 자동완성
  트리거 억제(`hasMarkedText()`)는 M3에서만 필요.
- **저장 위치 고정**: MVP 단일 문서라 경로 하드코딩. 다중 노트/파일 선택은 이후 확장(§11).
