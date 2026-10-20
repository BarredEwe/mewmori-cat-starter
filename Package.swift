// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CatStarter",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "CatStarter", targets: ["CatStarter"]),
        .executable(name: "CatInferenceDemo", targets: ["CatInferenceDemo"]),
        .library(name: "CatOCR", targets: ["CatOCR"]),
        .library(name: "CatPocketCore", targets: ["CatPocketCore"]),
        .executable(name: "CatBench", targets: ["CatBench"])
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/llama.swift", from: "2.9999.0")
    ],
    targets: [
        .target(name: "CatOCR"),
        .executableTarget(
            name: "CatStarter",
            dependencies: ["CatOCR"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "CatInferenceDemo",
            dependencies: [
                "CatOCR",
                .product(name: "LlamaSwift", package: "llama.swift")
            ]
        ),
        .target(
            name: "CatPocketCore",
            dependencies: [.product(name: "LlamaSwift", package: "llama.swift")]
        ),
        .executableTarget(
            name: "CatBench",
            dependencies: ["CatPocketCore"]
        ),
        .testTarget(
            name: "CatStarterTests",
            dependencies: ["CatStarter", "CatOCR"]
        )
    ]
)
