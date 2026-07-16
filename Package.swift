// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MINT",
    platforms: [
        // MLX는 Apple Silicon + macOS 14+ 필요
        .macOS(.v14)
    ],
    dependencies: [
        // 온디바이스 LLM 추론. MLXLLM/MLXLMCommon은 mlx-swift-examples에서
        // mlx-swift-lm 저장소로 이전됨.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // MLXArray 등 코어 타입 직접 사용 — 이어쓰기(continuation) 프롬프트는
        // 챗 템플릿 없이 수동 토크나이즈로 LMInput을 만든다.
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.4"),
        // Hugging Face 허브 다운로드 + 토크나이저.
        // mlx-swift-lm 3.x의 #huggingFaceLoadModelContainer 매크로(MLXHuggingFace)가
        // HubClient(swift-huggingface)와 AutoTokenizer(swift-transformers)로 확장된다.
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
        // 수식 블록 LaTeX 렌더링 (iosMath의 Swift 포트, CoreText 기반 네이티브).
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.5.0"),
    ],
    targets: [
        // 앱의 화면·로직은 라이브러리 타깃에 둔다.
        //  · SwiftUI 프리뷰는 executableTarget에서 ENABLE_DEBUG_DYLIB 제약으로 막히지만,
        //    라이브러리 타깃의 뷰는 프리뷰가 정상 동작한다.
        //  · PLAN의 "관심사 분리는 모듈로"(Editor/Inference/Storage) 방향과도 맞다.
        .target(
            name: "MINTCore",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "SwiftMath", package: "SwiftMath"),
            ],
            path: "Sources/MINTCore"
        ),
        // @main 진입점만 담은 얇은 실행 셸. 실제 화면/로직은 MINTCore에 있다.
        .executableTarget(
            name: "MINT",
            dependencies: ["MINTCore"],
            path: "Sources/MINT"
        ),
        // M2 추론 리스크 선검증 CLI (PLAN §6 M2).
        // Mac에서: swift run -c release MINTBench [--model <hf-id>] …
        .executableTarget(
            name: "MINTBench",
            dependencies: ["MINTCore"],
            path: "Sources/MINTBench"
        ),
        // 결정적 로직 회귀 테스트 (`swift test`). 모델·Metal을 건드리지 않는
        // 순수 로직만 — 원고 무결성(직렬화 왕복)이 첫 대상이다.
        .testTarget(
            name: "MINTCoreTests",
            dependencies: ["MINTCore"],
            path: "Tests/MINTCoreTests"
        ),
    ]
)
