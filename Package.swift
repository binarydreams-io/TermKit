// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "TermKit",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "TermKit", targets: ["TermKit"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/tayloraswift/swift-png",
      exact: "4.5.1"
    ),
    .package(
      url: "https://github.com/tayloraswift/swift-jpeg",
      exact: "2.1.0"
    )
  ],
  targets: [
    .target(
      name: "TermKit",
      dependencies: [
        .product(name: "PNG", package: "swift-png"),
        .product(name: "JPEG", package: "swift-jpeg")
      ],
      resources: [.copy("VERSION")]
    ),
    .testTarget(
      name: "TermKitTests",
      dependencies: ["TermKit"],
      resources: [.copy("Snapshots"), .copy("Fixtures")]
    )
  ]
)
