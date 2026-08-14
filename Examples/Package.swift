// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TermKitExamples",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TermKitPlayer", targets: ["TermKitPlayer"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "TermKitPlayer",
            dependencies: [
                .product(name: "TermKit", package: "TermKit")
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "TermKitPlayerPTYHarness"),
        .testTarget(
            name: "TermKitPlayerTests",
            dependencies: ["TermKitPlayer", "TermKitPlayerPTYHarness"],
            resources: [.copy("Snapshots")]
        ),
    ]
)
