// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TermKitConsumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "TermKit", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "TermKitConsumer",
            dependencies: [.product(name: "TermKit", package: "TermKit")]
        )
    ]
)
