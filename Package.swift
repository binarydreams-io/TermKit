// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let isBuildingDocumentation = Context.environment["TUIKIT_BUILD_DOCUMENTATION"] == "1"
let tuikitDocumentationExcludes = isBuildingDocumentation ? [] : ["TUIkit.docc"]
let tuikitDocumentationResources: [Resource] = isBuildingDocumentation ? [.copy("TUIkit.docc")] : []
let vendoredPNGSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("BareSlashRegexLiterals"),
    .enableUpcomingFeature("ConciseMagicFile"),
    .enableUpcomingFeature("ExistentialAny"),
]
let vendoredHashSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableExperimentalFeature("StrictConcurrency"),
    .define("DEBUG", .when(configuration: .debug)),
]

let package = Package(
    name: "SwiftTUI",
    // Minimum deployment targets for Apple platforms
    // Linux is automatically supported (no platform specification needed)
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TUIFoundation", targets: ["TUIFoundation"]),
        .library(name: "TUITerminal", targets: ["TUITerminal"]),
        .library(name: "TUIRenderer", targets: ["TUIRenderer"]),
        .library(name: "TUIViewGraph", targets: ["TUIViewGraph"]),
        .library(name: "TUILayout", targets: ["TUILayout"]),
        .library(name: "TUIAnimation", targets: ["TUIAnimation"]),
        .library(name: "TUIControls", targets: ["TUIControls"]),
        .library(name: "TUIDesign", targets: ["TUIDesign"]),
        .library(name: "TUIRichText", targets: ["TUIRichText"]),
        .library(name: "TUIAgentUI", targets: ["TUIAgentUI"]),
        .library(name: "TUIRuntime", targets: ["TUIRuntime"]),
        .library(name: "SwiftTUI", targets: ["SwiftTUI"]),
        .executable(name: "SwiftTUIShowcase", targets: ["SwiftTUIShowcase"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "TUIFoundation"),
        .target(name: "TUITerminal", dependencies: ["TUIFoundation"]),
        .target(name: "TUIRenderer", dependencies: ["TUIFoundation"]),
        .target(name: "TUIViewGraph", dependencies: ["TUIFoundation"]),
        .target(name: "TUILayout", dependencies: ["TUIFoundation", "TUIViewGraph"]),
        .target(name: "TUIAnimation", dependencies: ["TUIFoundation", "TUIViewGraph"]),
        .target(
            name: "TUIControls",
            dependencies: ["TUIFoundation", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIAnimation"]
        ),
        .target(
            name: "TUIDesign",
            dependencies: ["TUIFoundation", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIAnimation", "TUIControls"]
        ),
        .target(
            name: "TUIRichText",
            dependencies: ["TUIFoundation", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIControls", "TUIDesign"]
        ),
        .target(
            name: "TUIAgentUI",
            dependencies: ["TUIFoundation", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIAnimation", "TUIControls", "TUIDesign", "TUIRichText"]
        ),
        .target(
            name: "TUIRuntime",
            dependencies: ["TUIFoundation", "TUITerminal", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIAnimation", "TUIControls"]
        ),
        .target(
            name: "SwiftTUI",
            dependencies: ["TUIFoundation", "TUITerminal", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIAnimation", "TUIControls", "TUIDesign", "TUIRichText", "TUIAgentUI", "TUIRuntime"],
            resources: [.copy("VERSION")]
        ),
        .executableTarget(name: "SwiftTUIShowcase", dependencies: ["SwiftTUI"]),
        .executableTarget(name: "SwiftTUIShowcasePTYHarness"),

        // Legacy TUIkit Regression targets begin here. They preserve internal regression and
        // provenance evidence, including the vendored pure Swift image codecs. No TUIkit or
        // TUIkitVendor target is exposed as a public package product.
        .target(
            name: "TUIkitVendorBaseDigits",
            path: "Vendor/swift-hash/Sources/BaseDigits",
            swiftSettings: vendoredHashSettings
        ),
        .target(
            name: "TUIkitVendorBase16",
            dependencies: ["TUIkitVendorBaseDigits"],
            path: "Vendor/swift-hash/Sources/Base16",
            swiftSettings: vendoredHashSettings
        ),
        .target(
            name: "TUIkitVendorCRC",
            dependencies: ["TUIkitVendorBase16"],
            path: "Vendor/swift-hash/Sources/CRC",
            swiftSettings: vendoredHashSettings
        ),
        .target(
            name: "TUIkitVendorLZ77",
            dependencies: ["TUIkitVendorCRC"],
            path: "Vendor/swift-png/Sources/LZ77",
            swiftSettings: vendoredPNGSettings
        ),
        .target(
            name: "TUIkitVendorPNG",
            dependencies: ["TUIkitVendorLZ77", "TUIkitVendorCRC"],
            path: "Vendor/swift-png/Sources/PNG",
            swiftSettings: vendoredPNGSettings
        ),
        .target(
            name: "TUIkitVendorJPEG",
            path: "Vendor/swift-jpeg/Sources/JPEG",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Legacy low-level targets (no dependencies).
        .target(name: "TUIkitCore"),
        .target(name: "TUIkitStyling"),

        // Legacy mid-level targets.
        .target(name: "TUIkitView", dependencies: ["TUIkitCore"]),
        .target(
            name: "TUIkitImage",
            dependencies: [
                "TUIkitStyling",
                "TUIkitVendorPNG",
                "TUIkitVendorJPEG",
            ]
        ),

        // Legacy aggregate target.
        .target(
            name: "TUIkit",
            dependencies: ["TUIkitCore", "TUIkitStyling", "TUIkitImage", "TUIkitView"],
            exclude: tuikitDocumentationExcludes,
            resources: [.copy("Localization/translations"), .copy("VERSION")] + tuikitDocumentationResources
        ),

        // Legacy example, test support, and module regression tests.
        .executableTarget(
            name: "TUIkitExample",
            dependencies: ["TUIkit"],
            resources: [.copy("Resources")]
        ),
        .target(
            name: "TUIkitTestSupport",
            path: "Tests/TUIkitTestSupport"
        ),
        .testTarget(name: "TUIkitCoreTests", dependencies: ["TUIkitCore"]),
        .testTarget(name: "TUIkitStylingTests", dependencies: ["TUIkitStyling"]),
        .testTarget(name: "TUIkitViewTests", dependencies: ["TUIkitCore", "TUIkitView"]),
        .testTarget(name: "TUIkitImageTests", dependencies: ["TUIkitImage"]),
        // Current SwiftTUI module, integration, showcase, and performance tests.
        .testTarget(name: "TUIFoundationTests", dependencies: ["TUIFoundation"]),
        .testTarget(name: "TUITerminalTests", dependencies: ["TUITerminal"]),
        .testTarget(name: "TUIRendererTests", dependencies: ["TUIFoundation", "TUIRenderer"]),
        .testTarget(name: "TUIViewGraphTests", dependencies: ["TUIFoundation", "TUIViewGraph"]),
        .testTarget(name: "TUILayoutTests", dependencies: ["TUIFoundation", "TUIViewGraph", "TUILayout"]),
        .testTarget(name: "TUIAnimationTests", dependencies: ["TUIFoundation", "TUIViewGraph", "TUIAnimation", "TUIControls"]),
        .testTarget(name: "TUIControlsTests", dependencies: ["TUIFoundation", "TUIRenderer", "TUILayout", "TUIControls"]),
        .testTarget(name: "TUIDesignTests", dependencies: ["TUIFoundation", "TUIRenderer", "TUIAnimation", "TUIControls", "TUIDesign"]),
        .testTarget(name: "TUIRichTextTests", dependencies: ["TUIFoundation", "TUIRichText"]),
        .testTarget(
            name: "TUIAgentUITests",
            dependencies: ["TUIFoundation", "TUILayout", "TUIAnimation", "TUIAgentUI"],
            resources: [.copy("Snapshots")]
        ),
        .testTarget(
            name: "TUIRuntimeTests",
            dependencies: ["TUIFoundation", "TUITerminal", "TUIRenderer", "TUIViewGraph", "TUILayout", "TUIAnimation", "TUIControls", "TUIDesign", "TUIRichText", "TUIAgentUI", "TUIRuntime"]
        ),
        .testTarget(name: "SwiftTUIIntegrationTests", dependencies: ["SwiftTUI"]),
        .testTarget(
            name: "SwiftTUIShowcaseSmokeTests",
            dependencies: ["SwiftTUIShowcase", "SwiftTUIShowcasePTYHarness"]
        ),
        .testTarget(
            name: "TUIPerformanceTests",
            dependencies: ["TUIAgentUI", "TUIAnimation", "TUIFoundation", "TUILayout", "TUIRenderer", "TUIRuntime", "TUITerminal"]
        ),
        // Final Legacy TUIkit Regression integration target. This closes the internal legacy block.
        .testTarget(
            name: "TUIkitTests",
            dependencies: ["TUIkit", "TUIkitTestSupport"]
        ),
    ]
)
