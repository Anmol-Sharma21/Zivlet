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
                "ZivletRuntime", "ZivletTriggerHost", "ZivletWheel", "ZivletActions", "ZivletSettings", "ZivletUI",
                "ZivletNotchCore", "ZivletNotch",
            ])
    ],
    targets: [
        .target(name: "ZivletCore", swiftSettings: strict),
        .target(name: "ZivletTrigger", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletWheelCore", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletTriggerHost", dependencies: ["ZivletTrigger"], swiftSettings: shell),
        .target(name: "ZivletWheel", dependencies: ["ZivletWheelCore", "ZivletTrigger"], swiftSettings: shell),
        // The notch island (design/19, D-N1): pure geometry, layout, machine, arbiter; the AppKit panel and hosts.
        .target(name: "ZivletNotchCore", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletNotch", dependencies: ["ZivletNotchCore"], swiftSettings: shell),
        .target(name: "ZivletEngineKit", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "EngineMedia", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        // Built by Vendor/ensure-native.sh before every make target that reads this manifest (D-M4-9).
        .binaryTarget(name: "CWebP", path: "../../Vendor/out/CWebP.xcframework"),
        .binaryTarget(name: "CZivletSVG", path: "../../Vendor/out/CZivletSVG.xcframework"),
        .target(name: "EngineImage", dependencies: ["ZivletEngineKit", "CWebP", "CZivletSVG"], swiftSettings: strict),
        .target(
            name: "ZivletRuntime", dependencies: ["ZivletEngineKit", "EngineMedia", "EngineImage"],
            swiftSettings: strict),
        // Copy, Copy Path, AirDrop, Move, Terminal (02 §6): AppKit side effects behind small ports.
        .target(name: "ZivletActions", dependencies: ["ZivletCore", "ZivletRuntime"], swiftSettings: shell),
        // Versioned, validated settings values and their UserDefaults store (03b §8.1); no AppKit.
        .target(name: "ZivletSettings", dependencies: ["ZivletTrigger"], swiftSettings: strict),
        // The app shell's windows and panels: Settings, the status menu model, onboarding, the HUD (14 §3).
        .target(
            name: "ZivletUI",
            dependencies: [
                "ZivletCore", "ZivletTrigger", "ZivletWheelCore", "ZivletEngineKit", "ZivletRuntime", "ZivletActions",
                "ZivletSettings", "ZivletNotchCore", "ZivletNotch",
            ], swiftSettings: shell),
        // Writes the image fixtures for Fixtures/generate.sh (P1-60, D-M4-15); a dev tool, not shipped or gated.
        .executableTarget(name: "zivlet-fixtures", dependencies: ["CWebP"], swiftSettings: strict),
        // Times one engine conversion for Scripts/bench.sh (P1-63); a dev tool, not shipped or gated.
        .executableTarget(
            name: "zivlet-bench", dependencies: ["ZivletCore", "ZivletEngineKit", "EngineImage", "EngineMedia"],
            swiftSettings: strict),
        .target(name: "TestSupport", path: "Tests/TestSupport", swiftSettings: strict),
        .target(
            name: "EngineTestSupport", dependencies: ["ZivletEngineKit"], path: "Tests/EngineTestSupport",
            swiftSettings: strict),

        // Display fixtures, a fake display provider and a manual clock for the notch and HUD test bundles.
        .target(
            name: "NotchTestSupport", dependencies: ["ZivletNotch", "ZivletNotchCore", "ZivletCore"],
            path: "Tests/NotchTestSupport", swiftSettings: strict),

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
            name: "EngineMediaTests", dependencies: ["EngineMedia", "TestSupport", "EngineTestSupport"],
            resources: [.copy("Goldens")],
            swiftSettings: strict),
        .testTarget(
            name: "EngineImageTests", dependencies: ["EngineImage", "EngineTestSupport", "CWebP", "CZivletSVG"],
            resources: [.copy("Goldens")], swiftSettings: strict),
        .testTarget(
            name: "ZivletRuntimeTests", dependencies: ["ZivletRuntime", "EngineTestSupport"], swiftSettings: strict),
        .testTarget(
            name: "ZivletActionsTests", dependencies: ["ZivletActions", "TestSupport"], swiftSettings: shell),
        .testTarget(name: "ZivletSettingsTests", dependencies: ["ZivletSettings"], swiftSettings: strict),
        .testTarget(
            name: "ZivletUITests", dependencies: ["ZivletUI", "TestSupport", "NotchTestSupport"], swiftSettings: shell),
        .testTarget(
            name: "ZivletNotchCoreTests", dependencies: ["ZivletNotchCore", "ZivletCore", "NotchTestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletNotchTests",
            dependencies: ["ZivletNotch", "ZivletNotchCore", "ZivletCore", "NotchTestSupport"],
            swiftSettings: shell),
        // The 161-pair matrix through the real pipeline (P1-61); conversions run only with ZIVLET_MATRIX=subset|full.
        .testTarget(
            name: "ZivletMatrixTests",
            dependencies: ["ZivletRuntime", "ZivletCore", "ZivletEngineKit", "EngineMedia", "EngineImage"],
            swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
