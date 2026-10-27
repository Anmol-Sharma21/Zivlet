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
                "ZivletNotchCore", "ZivletNotch", "ZivletShelfCore", "ZivletBox", "ZivletIPC",
                "ZivletWorkerCore", "EngineVision",
            ]),
        // What ZivletWorker.xpc links (P2-01): the image engine and the worker's service, nothing of the app shell.
        .library(
            name: "ZivletWorkerKit",
            targets: ["ZivletCore", "ZivletEngineKit", "EngineImage", "EngineVision", "ZivletIPC", "ZivletWorkerCore"]),
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
        // The Drop Box's data (D-M5b-1): boxes, items, bookmarks, the store and plans; Foundation only.
        .target(name: "ZivletShelfCore", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletEngineKit", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "EngineMedia", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        // The worker's messages, their protocol version, request validation and the peer rule (P2-01, plan 18c).
        .target(name: "ZivletIPC", dependencies: ["ZivletCore", "ZivletEngineKit", "EngineVision"], swiftSettings: strict),
        // The worker's service without XPC: validation, engines, cancel and the idle exit (P2-01, plan 18c C3).
        .target(
            name: "ZivletWorkerCore", dependencies: ["ZivletIPC", "ZivletCore", "ZivletEngineKit", "EngineVision"],
            swiftSettings: strict),
        // Built by Vendor/ensure-native.sh before every make target that reads this manifest (D-M4-9).
        .binaryTarget(name: "CWebP", path: "../../Vendor/out/CWebP.xcframework"),
        .binaryTarget(name: "CZivletSVG", path: "../../Vendor/out/CZivletSVG.xcframework"),
        .target(name: "EngineImage", dependencies: ["ZivletEngineKit", "CWebP", "CZivletSVG"], swiftSettings: strict),
        // Vision text recognition and PDF text for Copy Text (P2-51 base, P2-103); its calls run only in the worker.
        .target(name: "EngineVision", dependencies: ["ZivletCore", "ZivletEngineKit"], swiftSettings: strict),
        .target(
            name: "ZivletRuntime",
            dependencies: ["ZivletEngineKit", "EngineMedia", "EngineImage", "ZivletIPC", "EngineVision"],
            swiftSettings: strict),
        // Copy, Copy Path, AirDrop, Move, Terminal (02 §6): AppKit side effects behind small ports.
        .target(name: "ZivletActions", dependencies: ["ZivletCore", "ZivletRuntime"], swiftSettings: shell),
        // The Drop Box's panel, views, intake and controller (D-M5b-1), and the notch tray that drives it (stream D).
        .target(
            name: "ZivletBox",
            dependencies: [
                "ZivletCore", "ZivletShelfCore", "ZivletActions", "ZivletRuntime", "ZivletNotchCore", "ZivletNotch",
                "ZivletTrigger",
            ], swiftSettings: shell),
        // Versioned, validated settings values and their UserDefaults store (03b §8.1); no AppKit.
        .target(name: "ZivletSettings", dependencies: ["ZivletTrigger", "ZivletCore"], swiftSettings: strict),
        // The app shell's windows and panels: Settings, the status menu model, onboarding, the HUD (14 §3).
        .target(
            name: "ZivletUI",
            dependencies: [
                "ZivletCore", "ZivletTrigger", "ZivletWheelCore", "ZivletEngineKit", "ZivletRuntime", "ZivletActions",
                "ZivletSettings", "ZivletNotchCore", "ZivletNotch", "EngineVision",
            ], swiftSettings: shell),
        // Writes the image fixtures for Fixtures/generate.sh (P1-60, D-M4-15); a dev tool, not shipped or gated.
        .executableTarget(name: "zivlet-fixtures", dependencies: ["CWebP"], swiftSettings: strict),
        // Times one engine conversion for Scripts/bench.sh (P1-63); a dev tool, not shipped or gated.
        .executableTarget(
            name: "zivlet-bench", dependencies: ["ZivletCore", "ZivletEngineKit", "EngineImage", "EngineMedia"],
            swiftSettings: strict),
        // Scores and tunes the notch-proximity rule on drag traces (NB5, OS-M5b-1); a dev tool, not shipped or gated.
        .executableTarget(
            name: "zivlet-traces", dependencies: ["ZivletTrigger", "ZivletCore", "ZivletNotchCore"],
            swiftSettings: strict),
        .target(name: "TestSupport", path: "Tests/TestSupport", swiftSettings: strict),
        // A loopback worker transport (JSON both ways, crashes on demand) for the connection and retry tests.
        .target(
            name: "WorkerTestSupport",
            dependencies: ["ZivletRuntime", "ZivletWorkerCore", "ZivletIPC", "ZivletEngineKit", "EngineVision", "TestSupport"],
            path: "Tests/WorkerTestSupport", swiftSettings: strict),
        .target(
            name: "EngineTestSupport", dependencies: ["ZivletEngineKit"], path: "Tests/EngineTestSupport",
            swiftSettings: strict),
        // The CER tool and the 12 Hindi + English OCR fixtures rendered at test time (plan 18d, D-M6-11, D-M6-12).
        .target(
            name: "OCRTestSupport", path: "Tests/OCRTestSupport", resources: [.copy("Resources/ocr-fixtures.json")],
            swiftSettings: strict),

        // Seeded synthetic drags and the recorded-trace reader for the shake and proximity tests (D-M5b-15, P2-197).
        .target(
            name: "DragTraceSupport",
            dependencies: ["ZivletTrigger", "ZivletCore", "ZivletNotchCore", "TestSupport", "NotchTestSupport"],
            path: "Tests/DragTraceSupport", swiftSettings: strict),

        // Display fixtures, a fake display provider and a manual clock for the notch and HUD test bundles.
        .target(
            name: "NotchTestSupport", dependencies: ["ZivletNotch", "ZivletNotchCore", "ZivletCore"],
            path: "Tests/NotchTestSupport", swiftSettings: strict),

        .testTarget(name: "ZivletCoreTests", dependencies: ["ZivletCore"], swiftSettings: strict),
        .testTarget(
            name: "ZivletIPCTests",
            dependencies: ["ZivletIPC", "ZivletCore", "ZivletEngineKit", "EngineVision", "TestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletWorkerCoreTests",
            dependencies: [
                "ZivletWorkerCore", "ZivletIPC", "ZivletCore", "ZivletEngineKit", "EngineVision", "EngineTestSupport",
                "TestSupport", "OCRTestSupport", "WorkerTestSupport",
            ],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletTriggerTests",
            dependencies: ["ZivletTrigger", "ZivletCore", "TestSupport", "DragTraceSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletTracesToolTests",
            dependencies: ["zivlet-traces", "ZivletTrigger", "TestSupport", "DragTraceSupport"], swiftSettings: strict),
        .testTarget(
            name: "ZivletWheelCoreTests", dependencies: ["ZivletWheelCore", "TestSupport"], swiftSettings: strict),
        .testTarget(
            name: "ZivletTriggerHostTests",
            dependencies: ["ZivletTriggerHost", "ZivletTrigger", "ZivletCore", "TestSupport"],
            swiftSettings: shell),
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
            name: "EngineVisionTests", dependencies: ["EngineVision", "ZivletCore", "OCRTestSupport", "TestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletRuntimeTests",
            dependencies: [
                "ZivletRuntime", "EngineTestSupport", "TestSupport", "WorkerTestSupport", "ZivletIPC", "ZivletWorkerCore",
                "EngineVision",
            ], swiftSettings: strict),
        .testTarget(
            name: "ZivletActionsTests", dependencies: ["ZivletActions", "TestSupport"], swiftSettings: shell),
        .testTarget(name: "ZivletSettingsTests", dependencies: ["ZivletSettings", "ZivletCore"], swiftSettings: strict),
        .testTarget(
            name: "ZivletUITests", dependencies: ["ZivletUI", "TestSupport", "NotchTestSupport", "EngineVision"],
            swiftSettings: shell),
        .testTarget(
            name: "ZivletNotchCoreTests", dependencies: ["ZivletNotchCore", "ZivletCore", "NotchTestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletNotchTests",
            dependencies: ["ZivletNotch", "ZivletNotchCore", "ZivletCore", "NotchTestSupport"],
            swiftSettings: shell),
        .testTarget(
            name: "ZivletShelfCoreTests", dependencies: ["ZivletShelfCore", "ZivletCore", "TestSupport"],
            swiftSettings: strict),
        .testTarget(
            name: "ZivletBoxTests",
            dependencies: [
                "ZivletBox", "ZivletShelfCore", "ZivletActions", "ZivletRuntime", "ZivletTriggerHost", "ZivletCore",
                "ZivletNotch", "ZivletNotchCore", "ZivletTrigger", "TestSupport", "NotchTestSupport",
            ],
            swiftSettings: shell),
        // The 161-pair matrix through the real pipeline (P1-61); conversions run only with ZIVLET_MATRIX=subset|full.
        .testTarget(
            name: "ZivletMatrixTests",
            dependencies: ["ZivletRuntime", "ZivletCore", "ZivletEngineKit", "EngineMedia", "EngineImage"],
            swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
