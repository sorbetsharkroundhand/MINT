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
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3")
    ],
    targets: [
        // 앱의 화면·로직은 라이브러리 타깃에 둔다.
        //  · SwiftUI 프리뷰는 executableTarget에서 ENABLE_DEBUG_DYLIB 제약으로 막히지만,
        //    라이브러리 타깃의 뷰는 프리뷰가 정상 동작한다.
        //  · PLAN의 "관심사 분리는 모듈로"(Editor/Inference/Storage) 방향과도 맞다.
        .target(
            name: "MINTCore",
            dependencies: [
                // M0에서는 의존성 해석·컴파일만 검증(앱 코드에서 아직 import 안 함).
                // 실제 사용은 M2(추론 엔진)부터.
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ],
            path: "Sources/MINTCore"
        ),
        // @main 진입점만 담은 얇은 실행 셸. 실제 화면/로직은 MINTCore에 있다.
        .executableTarget(
            name: "MINT",
            dependencies: ["MINTCore"],
            path: "Sources/MINT"
        )
    ]
)
