// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MINTKoreanBackend",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MINTKoreanBackend", targets: ["MINTKoreanBackend"])],
    targets: [
        .binaryTarget(name: "Kiwi", path: "Artifacts/KiwiStatic.xcframework"),
        .target(name: "CKiwiBridge", dependencies: ["Kiwi"],
                linkerSettings: [.linkedLibrary("c++"), .linkedLibrary("z")]),
        .target(name: "MINTKoreanBackend", dependencies: ["CKiwiBridge"],
                resources: [.copy("Resources/Kiwi")]),
    ]
)
