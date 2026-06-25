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
        .executableTarget(
            name: "MINT",
            dependencies: [
                // M0에서는 의존성 해석·컴파일만 검증(앱 코드에서 아직 import 안 함).
                // 실제 사용은 M2(추론 엔진)부터.
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ],
            path: "Sources/MINT"
        )
    ]
)
