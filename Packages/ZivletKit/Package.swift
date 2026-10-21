// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode + the upcoming features of 04 §4.2; warnings are errors.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]
// AppKit/SwiftUI shell modules: main-actor by default (02 §6.1, SE-0466).
let shell: [SwiftSetting] = strict + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "ZivletKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "ZivletKit",
            targets: [
                "ZivletCore", "ZivletTrigger", "ZivletWheelCore", "ZivletEngineKit", "EngineMedia", "EngineImage",
                "ZivletRuntime", "ZivletTriggerHost", "ZivletWheel",
            ])
    ],
    targets: [
        .target(name: "ZivletCore", swiftSettings: strict),
        .target(name: "ZivletTrigger", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletWheelCore", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletTriggerHost", dependencies: ["ZivletTrigger"], swiftSettings: shell),
        .target(name: "ZivletWheel", dependencies: ["ZivletWheelCore", "ZivletTrigger"], swiftSettings: shell),
        .target(name: "ZivletEngineKit", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "EngineMedia", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        // Built by Vendor/ensure-native.sh before every make target that reads this manifest (D-M4-9).
        .binaryTarget(name: "CWebP", path: "../../Vendor/out/CWebP.xcframework"),
        .binaryTarget(name: "CZivletSVG", path: "../../Vendor/out/CZivletSVG.xcframework"),
        .target(name: "EngineImage", dependencies: ["ZivletEngineKit", "CWebP", "CZivletSVG"], swiftSettings: strict),
        .target(
            name: "ZivletRuntime", dependencies: ["ZivletEngineKit", "EngineMedia", "EngineImage"],
            swiftSettings: strict),
        .target(name: "TestSupport", path: "Tests/TestSupport", swiftSettings: strict),
        .target(
            name: "EngineTestSupport", dependencies: ["ZivletEngineKit"], path: "Tests/EngineTestSupport",
            swiftSettings: strict),

        .testTarget(name: "ZivletCoreTests", dependencies: ["ZivletCore"], swiftSettings: strict),
        .testTarget(
            name: "ZivletTriggerTests", dependencies: ["ZivletTrigger", "TestSupport"], swiftSettings: strict),
        .testTarget(
            name: "ZivletWheelCoreTests", dependencies: ["ZivletWheelCore", "TestSupport"], swiftSettings: strict),
        .testTarget(name: "ZivletTriggerHostTests", dependencies: ["ZivletTriggerHost"], swiftSettings: shell),
        .testTarget(name: "ZivletWheelTests", dependencies: ["ZivletWheel"], swiftSettings: shell),
        .testTarget(
            name: "ZivletEngineKitTests", dependencies: ["ZivletEngineKit", "EngineTestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "EngineMediaTests", dependencies: ["EngineMedia", "TestSupport", "EngineTestSupport"], resources: [.copy("Goldens")],
            swiftSettings: strict),
        .testTarget(
            name: "EngineImageTests", dependencies: ["EngineImage", "EngineTestSupport", "CWebP", "CZivletSVG"],
            resources: [.copy("Goldens")], swiftSettings: strict),
        .testTarget(
            name: "ZivletRuntimeTests", dependencies: ["ZivletRuntime", "EngineTestSupport"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
