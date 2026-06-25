# M0 — 스캐폴드 구현 계획

> 브랜치: `feat/m0-scaffold` · 상위 계획: [PLAN.md](../PLAN.md) §6 마일스톤 M0
> ⚠️ 빌드/실행 검증은 **Apple Silicon Mac의 Xcode**에서. (이 개발 환경은 Linux라 컴파일 불가)

## 🎯 목표
빌드되는 **빈 SwiftUI macOS 앱** 골격을 만들고 **`mlx-swift-lm` 의존성 연결**을 검증한다.
이 단계에는 자동완성·MLX 추론 코드가 **없다** — 껍데기 + 의존성 배선만.

## ✅ 완료 기준 (Definition of Done)
- [ ] `open Package.swift` → Xcode `⌘R` 로 빈 창이 뜬다
- [ ] `mlx-swift-lm` 의존성이 해석·컴파일된다 (Swift 6 툴체인 검증)
- [ ] 임시 에디터(`TextEditor`)에 **한글 타이핑**이 된다
- [ ] Mac에서 검증 통과 → `main` 머지 → 브랜치 삭제

## 📦 생성할 파일
| 파일 | 내용 요약 |
|------|-----------|
| `Package.swift` | swift-tools `6.0`, 플랫폼 `.macOS(.v14)`, 의존성 `mlx-swift-lm` `from: 3.31.3` (`MLXLLM`·`MLXLMCommon`), `executableTarget("MINT")` |
| `Sources/MINT/MINTApp.swift` | `@main struct MINTApp: App` → `WindowGroup { ContentView() }` |
| `Sources/MINT/ContentView.swift` | 임시 `TextEditor` (M1에서 `NSTextView` 래퍼로 교체) + 빈 상태 placeholder |
| `.gitignore` | `.build/`, `.swiftpm/`, `DerivedData/`, 모델 캐시(`*.safetensors` 등) |

### 핵심 의존성 선언 (Package.swift)
```swift
.package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3")
```
> M0에서는 의존성을 **선언만** 하고 앱 코드에서 `import` 하지 않는다 (빈 창 빌드 안정성 확보).
> 실제 사용은 **M2(추론 엔진)** 부터.

## 🔧 작업 순서
1. ✅ `feat/m0-scaffold` 브랜치 생성
2. ⏳ 위 4개 파일 작성 *(이 계획 검토·승인 후)*
3. 커밋: `feat: M0 스캐폴드 — SwiftUI 앱 셸 + mlx-swift-lm SPM`
4. push → **Mac에서 빌드 검증**
5. 통과 시 `main` 머지 + 브랜치 삭제, PLAN.md 로드맵 M0 체크

## 🧪 검증 절차 (네 Mac)
```bash
git fetch origin
git checkout feat/m0-scaffold
open Package.swift          # Xcode가 패키지로 엶
# MINT 스킴 선택 → ⌘R. 첫 빌드는 MLX 컴파일로 수 분 소요.
# → 빈 창이 뜨고 한글 타이핑이 되면 M0 성공.
```

## 🧭 결정 사항 / 열린 질문
- **앱 타깃 형태**: M0는 SPM `executableTarget`로 간다. 정식 `.xcodeproj` 앱 타깃
  (샌드박스·`Info.plist`·entitlements)이 필요해지면 이후 전환. → *M0 빌드 결과 보고 판단.*
- **잠재 리스크**: SPM 기반 SwiftUI 실행 타깃이 정식 앱 번들과 동작 차이(메뉴·활성화 등)가
  있을 수 있음. 문제가 보이면 `.xcodeproj`로 전환 검토.
