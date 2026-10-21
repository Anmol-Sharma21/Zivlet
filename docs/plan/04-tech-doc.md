# 04 — Zivlet Engineering Handbook

Date: 2026-10-20. Scope: Phase 0 (skeleton and spikes) and Phase 1 (MVP slice: trigger, wheel, 153 media/image pairs, 5 actions). Later phases extend this handbook; they don't replace it.
Inputs: [00-decisions](../design/00-decisions.md), [10-tech-strategy](../design/10-tech-strategy.md) §7–§13 (its `[challenge]` notes win), [11-media-engine](../design/11-media-engine.md) §6, §8, §14, [14-app-platform](../design/14-app-platform.md) §1, §3.6, §5, [15-strategy-challenge](../design/15-strategy-challenge.md) §4, C-10.

Tags: **VERIFIED** = run on the dev Mac on 2026-10-20 · **DECISION** = this document decides it · **TO VERIFY** = check before relying on it.

Deviations from 10-tech-strategy §7.1, all **DECISION**:

| 10 §7.1 says | This handbook | Why |
|---|---|---|
| Committed `Zivlet.xcodeproj` with synchronized folders | `project.yml` (XcodeGen 2.45) generates the project. The generated project is **not committed**. | No pbxproj merge conflicts. Settings stay reviewable as text. |
| `ZivletEngines` dynamic framework | Phase 0–1 links the engines statically into the app. The dynamic product arrives with `ZivletWorker.xpc` in Phase 2. | Only one process links the engines until the worker exists (YAGNI). |
| Targets for Worker, zivlet-js, CLI, FinderSync | Absent in Phase 0–1 | Phase 2 / 2 / 3 / 1.x respectively. |

---

## 1. Toolchain

### 1.1 Versions (VERIFIED)

| Component | Version | Location | Verified with |
|---|---|---|---|
| Dev Mac OS | macOS 27.0 (26A428), arm64 | — | `sw_vers`, `uname -m` |
| Xcode | 27.0 (27A266a) | `/Applications/Xcode.app` | `DEVELOPER_DIR=… xcodebuild -version` |
| Swift | 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1) | Xcode toolchain | `swift --version` |
| macOS SDK | MacOSX27.0.sdk; builds target `arm64-apple-macos26.0` | Xcode | swiftc invocation in the build log |
| XcodeGen | 2.45.4 | `/opt/homebrew/bin/xcodegen` | `xcodegen --version` |
| swift-format | bundled (`swift format`) | Xcode toolchain | `swift format --version` |
| llvm-cov | bundled | `xcrun llvm-cov` | §6.8 run |
| ffmpeg / ffprobe (dev only) | 8.1.2 (Homebrew, GPL, shared) | `/opt/homebrew/bin` | `ffmpeg -version` |
| gh | present | `/opt/homebrew/bin/gh` | `which gh` |
| git | 2.54.0 (Apple Git-157) | `/usr/bin/git` | `git --version` |
| git-lfs, tart | not installed | — | install when needed (§6.5, §9.1) [critic3: §9.3 does not exist] |

```text
$ DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
Xcode 27.0
Build version 27A266a
$ swift --version
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx27.0.0
```

### 1.2 Rules

| Rule | Detail |
|---|---|
| Always export `DEVELOPER_DIR` | `xcode-select -p` returns `/Library/Developer/CommandLineTools`, which has no Xcode SDK, no XCTest and no `xcodebuild` actions. Every script sources `Scripts/env.sh`. That script exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and fails fast if the path is missing. Don't run `sudo xcode-select -s`; leave the owner's machine as it is. |
| Known log noise | `xcodebuild` prints `DVTCoreDeviceCore` plug-in load errors and "CoreSimulator is out of date". Both are harmless for macOS-only builds (VERIFIED: the build still succeeds). Filter them in scripts with `grep -v DVTPlugIn`. |
| OS skew | The dev Mac runs 27.0 but the minimum is 26.0. Deployment target 26.0 plus warnings-as-errors turns an unguarded 27-only API into a compile error. G-0 re-probes runtime behaviour on 26.x (10 §13). |
| Swift language mode | Swift 6, complete strict concurrency, in both the package and the Xcode targets. |
| Manifest tools version | `// swift-tools-version: 6.2`. It's the lowest version that has `.defaultIsolation` and `.treatAllWarnings` (VERIFIED: compiles under 6.4). Raise it only when a newer manifest API is needed. |
| Homebrew | Build-time tools only. Nothing from Homebrew is linked into a shipped binary. The only exception is dev-only ffmpeg *execution* (§7.1). |

### 1.3 Bootstrap (`Scripts/bootstrap.sh`)

| Step | Command | Fails when |
|---|---|---|
| Toolchain check | `xcodebuild -version` reports `Xcode 27.*`; `swift --version` reports `6.4` | wrong Xcode |
| Tools | `brew install xcodegen ffmpeg` (dev), plus `pkgconf cmake meson ninja autoconf automake libtool` (vendor builds only) | missing brew |
| Project | `xcodegen generate --spec project.yml` | spec error |
| Resolve | `xcodebuild -resolvePackageDependencies -project Zivlet.xcodeproj` | network or pin mismatch |
| Hooks | `git config core.hooksPath Scripts/hooks` | — |

---

## 2. Repository layout (Phase 0–1, exact)

```text
Zivlet/                               # repo root (GitHub repo name decided at O-10/O-12)
  .github/
    workflows/ ci.yml  vendor.yml  nightly.yml  release.yml
    pull_request_template.md
  .gitignore  .swift-format  LICENSE (GPL-3.0-or-later text)  README.md  CONTRIBUTING.md (DCO)
  project.yml                         # XcodeGen spec; Zivlet.xcodeproj is generated and ignored
  App/
    ZivletApp.swift                  # @main; composition root only (wires Runtime, Trigger, Wheel, UI, Sparkle)
    AppServices.swift                 # builds the dependency graph; no logic
    Assets.xcassets/                  # own icon and symbols (original artwork only)
    Localizable.xcstrings
  Config/
    Base.xcconfig  Debug.xcconfig  Release.xcconfig
    Zivlet.entitlements              # empty dict in Phase 0–1 (§3.4)
    ExportOptions.plist               # method = developer-id
  Packages/ZivletKit/
    Package.swift  Package.resolved
    Sources/
      ZivletCore/                    # Format, Catalog (275 pairs as data), JobRequest/Result, OutputNamer, JobError, Log
      ZivletEngineKit/               # Engine, ExecutionPlan, JobWorkspace, ProgressSink, SubprocessRunner, EngineLocator, CapabilityProbe
      EngineMedia/                    # MediaProbe, Plan/{Audio,Video,GIF}Plans, ProgressParser, MediaOutputVerifier
      EngineImage/                    # ImageIO pipeline, Quartz (QZ) path, WebP encoder bridge
      ZivletRuntime/                 # JobScheduler, Publisher, NameReserver, UndoLog, OrphanReaper, BatchAggregator
      ZivletTrigger/                 # TriggerMachine (pure), InputSample, AppKitSampler
      ZivletWheel/                   # WheelPanel, WheelDropView, WheelModel, WheelGeometry, PetalShape, glass/solid themes
      ZivletUI/                      # Settings, onboarding, HUD, result card, Actions (AirDrop, Copy, Move, Copy Path, Terminal)
      CWebP/                          # Phase 1: binaryTarget(path:) → Vendor/out/CWebP.xcframework
    Tests/
      ZivletCoreTests/  ZivletEngineKitTests/  EngineMediaTests/  EngineImageTests/
      ZivletRuntimeTests/  ZivletTriggerTests/  ZivletWheelTests/  IntegrationTests/
      TestSupport/                    # shared fixture generators, ffprobe asserts, golden helpers (a plain target)
  UITests/
    ZivletUITests/                   # XCUITest; keyboard-mode wheel via launch arguments (§6.6)
  Fixtures/
    generate.sh                       # lavfi + sips corpus for manual QA; tests generate their own (§6.4)
    traces/                           # recorded TriggerMachine JSON traces
    hostile/                          # small refusal fixtures (HLS-as-.mp4, ffconcat-as-.mkv) — text files, committed
  Vendor/
    versions.lock                     # name, version/commit, URL, sha256 (one per line)
    build-media.sh  verify-media.sh  build-native.sh
    patches/                          # lame-3.100-sym.patch, vorbis-1.3.7-cpusubtype.patch, …
    licences/                         # upstream licence texts, copied at vendoring time
  Scripts/
    env.sh  bootstrap.sh  test.sh  coverage.sh  lint.sh  embed-helpers.sh
    sign-helpers.sh  verify-signatures.sh  make-dmg.sh  size-gate.sh  source-bundle.sh  appcast.sh
    hooks/ commit-msg  pre-commit
  docs/                               # design and plan docs
```

`.gitignore` (minimum): `Zivlet.xcodeproj/`, `App/Info.plist` (generated), `*.xcworkspace/` (generated), `.build/`, `build/`, `DerivedData/`, `Vendor/src/`, `Vendor/build/`, `Vendor/out/`, `*.profdata`, `.DS_Store`, `*.p12`, `*.p8`, `AuthKey*`.

---

## 3. `project.yml` design

### 3.1 Targets

| Target | Type | Phase | Sources | Links | Notes |
|---|---|---|---|---|---|
| `Zivlet` | `application` | 0 | `App/` | ZivletKit products, Sparkle | Menu-bar agent; post-build `embed-helpers.sh` |
| `ZivletUITests` | `bundle.ui-testing` | 1 | `UITests/ZivletUITests` | — | Test host: `Zivlet` |
| `ZivletWorker` | `xpc-service` | 2 | `Worker/` | `ZivletEngines` (dynamic) | Not in Phase 0–1 |
| `zivlet-js` | `tool` | 2 | `JSHelper/` | — | `allow-jit` |
| `zivlet` | `tool` | 3 | package executable | — | CLI |

Schemes: `Zivlet` (build + UI tests). Package unit tests run with `swift test`, not through the scheme. This keeps one source of truth for coverage (§6.8).

### 3.2 Build settings (`Config/Base.xcconfig`, referenced from `project.yml`)

| Setting | Value | Reason |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | `26.0` | 00-decisions |
| `ARCHS` / `ONLY_ACTIVE_ARCH` | `arm64` / `NO` in Release | O-13 arm64-only |
| `SWIFT_VERSION` | `6.0` | Swift 6 language mode (`-swift-version 6`, VERIFIED) |
| `SWIFT_STRICT_CONCURRENCY` | `complete` | |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | enables `NonisolatedNonsendingByDefault` + `InferIsolatedConformances` (VERIFIED in the swiftc flags) |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` (app target only) | `-default-isolation MainActor` (VERIFIED) |
| `SWIFT_TREAT_WARNINGS_AS_ERRORS` / `GCC_TREAT_WARNINGS_AS_ERRORS` | `YES` | |
| `ENABLE_HARDENED_RUNTIME` | `YES` | required for notarization |
| `OTHER_CODE_SIGN_FLAGS` | `--options=runtime` (Debug); Release gets runtime + timestamp from Xcode and `sign-helpers.sh` | VERIFIED: an ad-hoc **Debug** build without this flag is signed `flags=0x2(adhoc)`, with no runtime flag. Adding it gives `0x10002(adhoc,runtime)`. Release already had it. |
| `CODE_SIGN_STYLE` | `Manual` | |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc) until O-11. Then `Developer ID Application` in Release only, overridden by CI | §8 |
| `DEVELOPMENT_TEAM` | empty until O-11. Then the Team ID, passed by CI as an environment variable, never committed | |
| `PRODUCT_BUNDLE_IDENTIFIER` | `app.zivlet.Zivlet` | O-10 placeholder |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | SemVer / monotonically increasing integer | Sparkle compares `CFBundleVersion` |
| `DEAD_CODE_STRIPPING`, `STRIP_INSTALLED_PRODUCT` (Release) | `YES` | size gate |
| `DEBUG_INFORMATION_FORMAT` (Release) | `dwarf-with-dsym` | dSYMs uploaded per release |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` for `Zivlet` only | `embed-helpers.sh` reads `Vendor/out` |

### 3.3 Info.plist keys (`info.properties`, `GENERATE_INFOPLIST_FILE = NO`)

| Key | Value | Phase |
|---|---|---|
| `CFBundleIdentifier` | `$(PRODUCT_BUNDLE_IDENTIFIER)` | 0 |
| `CFBundleName` / `CFBundleDisplayName` | `Zivlet` | 0 |
| `CFBundleShortVersionString` / `CFBundleVersion` | `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` | 0 |
| `LSUIElement` | `true` (agent app: no Dock icon, menu-bar extra only) | 0 |
| `LSMinimumSystemVersion` | `26.0` | 0 |
| `LSApplicationCategoryType` | `public.app-category.utilities` | 0 |
| `NSHumanReadableCopyright` | `Copyright © 2026 Zivlet contributors. GPL-3.0-or-later.` | 0 |
| `SUFeedURL` / `SUPublicEDKey` / `SUEnableInstallerLauncherService` | appcast URL / EdDSA public key / `NO` (unsandboxed) | 0 (hello update) |
| `SUEnableSystemProfiling` | `NO` | 0 |
| `CFBundleURLTypes` | `zivlet` scheme (opens UI only, never runs a job; 10 §8.9) | 1 |
| `NSServices` | Services menu entry | 2 |
| `NSAppleEventsUsageDescription` | only when the O-17 opt-in features land, together with the entitlement | 3 |

Verified with the prototype: `LSUIElement => true`, `LSMinimumSystemVersion => "26.0"`, `CFBundleIdentifier => "app.zivlet.Zivlet"` in the built bundle.

### 3.4 Entitlements

| Binary | Phase 0–1 | Later |
|---|---|---|
| `Zivlet.app` | empty `<dict/>`. Not sandboxed; no `get-task-allow` in Release. | `automation.apple-events` (O-17, Phase 3). FinderSync app group `<TEAMID>.app.zivlet` (1.x, 15 C-22). |
| `Contents/Helpers/ffmpeg`, `ffprobe` | none | none |
| `zivlet-js` | — | `com.apple.security.cs.allow-jit` |
| `ZivletWorker.xpc` | — | none |

Debug builds get `com.apple.security.get-task-allow` injected by Xcode (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES`, VERIFIED). Release must not have it, and `verify-signatures.sh` checks that.

### 3.5 Skeleton (abridged; settings live in the xcconfigs)

```yaml
name: Zivlet
options:
  bundleIdPrefix: app.zivlet
  deploymentTarget: { macOS: "26.0" }
  xcodeVersion: "27.0"
  createIntermediateGroups: true
configFiles: { Debug: Config/Debug.xcconfig, Release: Config/Release.xcconfig }
packages:
  ZivletKit: { path: Packages/ZivletKit }
  Sparkle: { url: https://github.com/sparkle-project/Sparkle, exactVersion: 2.10.0 }
targets:
  Zivlet:
    type: application
    platform: macOS
    sources: [App]
    dependencies:
      - package: ZivletKit
        product: ZivletKit
      - package: Sparkle
    info:
      path: App/Info.plist            # generated by XcodeGen from these properties; ignored by git
      properties: { LSUIElement: true, LSMinimumSystemVersion: "26.0", ... }
    entitlements: { path: Config/Zivlet.entitlements }
    settings:
      base: { PRODUCT_BUNDLE_IDENTIFIER: app.zivlet.Zivlet, SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor }
    postBuildScripts:
      - name: Embed helpers
        script: '"$SRCROOT/Scripts/embed-helpers.sh"'
        basedOnDependencyAnalysis: false
  ZivletUITests:
    type: bundle.ui-testing
    platform: macOS
    sources: [UITests/ZivletUITests]
    dependencies: [{ target: Zivlet }]
```

VERIFIED: an equivalent spec generates and builds with XcodeGen 2.45.4 + Xcode 27, and the app is ad-hoc signed as `app.zivlet.Zivlet`.

---

## 4. `Package.swift` design

### 4.1 Modules in Phase 0–1 (subset of 10 §7.2)

| Target | Depends on | Isolation | Coverage gate |
|---|---|---|---|
| `ZivletCore` | Foundation | nonisolated | 80 % |
| `ZivletEngineKit` | Core, `Subprocess` | nonisolated, `@concurrent` work | 80 % |
| `EngineMedia` | EngineKit | nonisolated | 80 % |
| `EngineImage` | EngineKit, `CWebP` (Phase 1) | nonisolated | 80 % |
| `ZivletRuntime` | Core, EngineKit, EngineMedia, EngineImage | actors | 80 % |
| `ZivletTrigger` | Core | pure core; `AppKitSampler` is `@MainActor` | 80 % (sampler excluded) |
| `ZivletWheelCore` [critic3] | Core | nonisolated, pure (geometry, hit-test, slice lists; 02 §4.1, 06 index D1) | 80 % |
| `ZivletWheel` | WheelCore, Trigger, Core | `defaultIsolation(MainActor)` | views excluded (geometry is gated in WheelCore) |
| `ZivletUI` | Wheel, Runtime, `KeyboardShortcuts` | `defaultIsolation(MainActor)` | excluded (XCUITest) |
| `TestSupport` | Core, EngineKit | nonisolated | n/a |

Import rules (enforced by `Scripts/lint.sh` with grep over `Sources/<target>`):
- `ZivletCore`, `ZivletTrigger` and `ZivletWheelCore` import only Foundation, `UniformTypeIdentifiers`, `Synchronization` and `os` [critic3: aligned with 02 §4.2 R1, which omitted `os`; logging needs it].
- No engine module imports AppKit or SwiftUI.
- `ZivletTrigger`, `ZivletWheelCore` and `ZivletWheel` never import engine modules.
- Requests, plans and results are `Codable & Sendable & Equatable` from day one, so moving them across XPC in Phase 2 is mechanical.

### 4.2 Manifest skeleton

```swift
// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]
let ui = strict + [.defaultIsolation(MainActor.self)]
let devEngines: SwiftSetting = .define("ZIVLET_ALLOW_SYSTEM_ENGINES", .when(configuration: .debug))

let package = Package(
    name: "ZivletKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ZivletKit", targets: ["ZivletUI", "ZivletWheel", "ZivletTrigger", "ZivletRuntime"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess", exact: "1.0.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "ZivletCore", swiftSettings: strict),
        .target(name: "ZivletEngineKit",
                dependencies: ["ZivletCore", .product(name: "Subprocess", package: "swift-subprocess")],
                swiftSettings: strict + [devEngines]),
        .target(name: "EngineMedia", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        .target(name: "EngineImage", dependencies: ["ZivletEngineKit"], swiftSettings: strict),
        .target(name: "ZivletRuntime", dependencies: ["ZivletEngineKit", "EngineMedia", "EngineImage"], swiftSettings: strict),
        .target(name: "ZivletTrigger", dependencies: ["ZivletCore"], swiftSettings: strict),
        .target(name: "ZivletWheel", dependencies: ["ZivletTrigger", "ZivletCore"], swiftSettings: ui),
        .target(name: "ZivletUI", dependencies: ["ZivletWheel", "ZivletRuntime", "KeyboardShortcuts"], swiftSettings: ui),
        .target(name: "TestSupport", dependencies: ["ZivletEngineKit"], path: "Tests/TestSupport", swiftSettings: strict),
        .testTarget(name: "ZivletCoreTests", dependencies: ["ZivletCore", "TestSupport"],
                    resources: [.copy("Goldens")], swiftSettings: strict),
        // … one test target per source target, plus IntegrationTests (§6.4)
    ]
)
```

| Item | Rule |
|---|---|
| Version pins | `exact:` for every dependency. `Package.resolved` is committed. Upgrades go in a `chore(deps):` PR. |
| Allowed dependencies (Phase 0–1) | swift-subprocess 1.0.2, KeyboardShortcuts 3.1.0, Sparkle 2.10.0 (in the app target, not the package). Anything new needs a licence row in 10 §10.2 first. |
| Binary targets | `CWebP` = `.binaryTarget(name:path:)` pointing at `Vendor/out/CWebP.xcframework`, built by `build-native.sh`. Phase 0 has no binary targets. |
| `ZIVLET_ALLOW_SYSTEM_ENGINES` | Defined only in Debug. Gates the Homebrew fallback in `EngineLocator` (§7.1). |

VERIFIED: a reduced manifest with these settings builds and its Swift Testing suite passes under Swift 6.4.

---

## 5. Coding conventions

### 5.1 Rules and enforcement

| Area | Rule | Enforced by |
|---|---|---|
| Format | `swift format` with the committed `.swift-format`: 4-space indent, 120 columns, ordered imports | `swift format lint --strict -r App Packages UITests` in `lint.sh` and CI |
| Naming | Types `UpperCamelCase`; values `lowerCamelCase`; booleans read as claims (`isPlayable`, `hasFileTypes`). No abbreviations except Apple-standard ones (URL, ID, UTI). | review |
| Immutability | Models are `struct`s with `let` properties. Change a value with a copy helper (`request.with(options:)`) that returns a new value. No `var` in public model types. Shared mutable state lives only in actors (`JobScheduler`, `NameReserver`, `UndoLog`) or `@MainActor @Observable` view models. | review; lint flags `public var` in `ZivletCore` |
| Pure state machines | `TriggerMachine.step(_:) -> TriggerStep` returns `(next: TriggerMachine, effects: [TriggerEffect])`, never `mutating`. Same pattern for `WheelModel` reducers and `ProgressParser`. | review, tests |
| File size | 200–400 lines typical, **800 hard cap** | `lint.sh` (`wc -l` over `*.swift`, fails above 800, warns above 400) |
| Function size | < 50 lines; nesting ≤ 3 levels (4 is the hard cap); use early `guard` exits | swift-format rules plus review |
| Magic numbers | Named constants in a `…Constants` enum near their use, e.g. `WheelGeometry.petalGapDegrees` or `SubprocessRunner.interruptGrace = .milliseconds(800)` | review |
| Errors | Every engine and runtime boundary throws `JobError` (10 §8.4 taxonomy) through typed throws: `throws(JobError)`. No empty `catch`. `try?` only when the fallback is explicit and commented. `fatalError` only for broken invariants that can't be recovered. Every user-facing error carries copy plus a `Show details` payload. | review; lint flags `catch {}` |
| Input validation | Validate at each boundary: drag pasteboard URLs (file URLs only, must exist and be readable, must not be a symlink loop), content sniffing before choosing an engine, ffprobe JSON (decode with `Codable`, reject missing required fields), settings (`Codable` with defaults), `zivlet://` URLs (allow-list of verbs), environment variables (Debug only). Fail fast with a typed error. | tests per boundary |
| Concurrency | No `DispatchQueue`, except the memory-pressure source. No `Task.detached`. `@unchecked Sendable` and `nonisolated(unsafe)` need a `// SAFETY:` comment and reviewer sign-off. Heavy work is `@concurrent`. | grep in `lint.sh` |
| Dependencies | Inject protocols for clock, file system, process runner and locator, so tests never need the real ones unless they're integration tests | review |
| Strings | User-facing text goes through `String(localized:)` in String Catalogs (O-15) | review |
| Comments | `///` on public API. A comment explains why, never what. | review |
| Clean-room | No code, assets or strings copied from the reference app or Open-Tangerine. Copy is written fresh. | PR template checkbox |

### 5.2 Logging (`os.Logger`; no `print`)

- One factory: `Log.logger(.media)` returns `Logger(subsystem: "app.zivlet.Zivlet", category: "media")`.
- `print`, `debugPrint`, `dump` and `NSLog` are banned in `Sources/` and `App/` (`lint.sh` greps for them). Tests may use Swift Testing `Attachment` or `#expect` messages instead.

| Category | Owner module | Category | Owner module |
|---|---|---|---|
| `trigger` | ZivletTrigger | `image` | EngineImage |
| `wheel` | ZivletWheel | `pdf`, `docs`, `render`, `archive`, `metadata`, `vision`, `office` | later phases |
| `scheduler` | ZivletRuntime | `update` | App (Sparkle) |
| `worker` | Runtime (Phase 2) | `actions` | ZivletUI |
| `media` | EngineMedia | `probe` | EngineKit (capability probe) |

| Level | Use |
|---|---|
| `.debug` | argv (paths `privacy: .private`), sampler transitions |
| `.info` | job admitted, finished, cancelled |
| `.notice` | capability changes, fallbacks taken |
| `.error` | job failure with the 64 KB stderr tail (`.private`) |
| `.fault` | broken invariants |

Paths and file names are always `privacy: .private`. `OSSignposter` intervals: `trigger.tapToFrame`, `drop.toAdmit`, `job.stage`.

---

## 6. Testing strategy

### 6.1 Layers

| Layer | Target(s) | Framework | Runs | Time budget |
|---|---|---|---|---|
| Unit: Core, naming, catalog | `ZivletCoreTests` | Swift Testing | every `swift test` | < 5 s |
| Planner goldens | `EngineMediaTests`, `EngineImageTests` | Swift Testing, `.tags(.golden)` | every run | < 5 s |
| Parsers | `EngineMediaTests` | Swift Testing | every run | < 1 s |
| Runtime | `ZivletRuntimeTests` | Swift Testing | every run | < 10 s |
| Trigger traces | `ZivletTriggerTests` | Swift Testing | every run | < 1 s |
| Wheel geometry + Solid snapshot | `ZivletWheelTests` | Swift Testing + `ImageRenderer` | every run | < 5 s |
| Integration (real ffmpeg, ImageIO) | `IntegrationTests`, `.tags(.integration)` | Swift Testing | PR (subset), nightly (all) | PR < 4 min |
| UI (windows, keyboard-mode wheel) | `ZivletUITests` | XCUITest | PR (smoke), nightly | < 5 min |
| Real drags | — | manual matrix (§6.7) | per release | — |

Tags in `TestSupport`: `.golden`, `.integration`, `.ffmpeg`, `.slow`. Selection: `swift test --filter` by target, or `--skip IntegrationTests` for the inner loop. Integration tests carry `.enabled(if: TestEngines.ffmpegAvailable)`, so a machine without ffmpeg reports them as skipped, never as passed. CI sets `ZIVLET_REQUIRE_ENGINES=1`, which turns a skip into a failure.

### 6.2 Unit tests (examples of required coverage)

| Subject | Cases |
|---|---|
| `Catalog` | `@Test(arguments: Catalog.allPairs)`: each of the 275 pairs resolves to a non-empty `[EngineID]` and an extension. Phase 1 marks 153 as enabled. |
| `OutputNamer` | `<base> <Suffix>.<ext>`; collisions add ` 2`, ` 3`; case-insensitive collision on APFS (`a.PNG` blocks `a.png`); `.tar.gz` double extensions; Unicode NFC/NFD; folder outputs have no extension |
| `JobError` | every case has non-empty copy and a details payload |
| `ProgressParser` | `N/A` fields, negative initial `out_time_us`, `progress=end`, split lines |
| `MediaProbe` decoding | missing fields, unknown codecs, rotated streams, no audio, audio only |

### 6.3 Planner goldens

- An input is `(MediaInfo fixture JSON, JobRequest, Capabilities)`. The output is the `ExecutionPlan` encoded as pretty, sorted-key JSON. Goldens live at `Tests/<Target>/Goldens/<route>/<case>.json`.
- On mismatch the test fails and attaches the actual JSON (`Attachment.record`).
- `ZIVLET_UPDATE_GOLDENS=1 swift test --filter EngineMediaTests` rewrites the goldens. The diff is reviewed in the PR like code.
- Required cases per route: remux vs re-encode, alpha kept, odd dimensions (853×479), HDR PQ input, > 2 channels into a stereo-only container, cover art, and WebM = `libvpx-vp9` + `libopus`. The codec is always named explicitly; we never rely on ffmpeg's default encoder choice.

### 6.4 Integration tests with real ffmpeg (lavfi fixtures)

Fixtures are **generated per test run** into a temp directory by `TestSupport.FixtureFactory`, with a cache keyed by the argv hash. Nothing binary is committed in Phase 0–1.

| Fixture | Generator argv (after `ffmpeg -nostdin -hide_banner -loglevel error -y`) |
|---|---|
| A/V MOV 2 s | `-f lavfi -i testsrc2=size=320x240:rate=30:duration=2 -f lavfi -i sine=frequency=440:sample_rate=48000:duration=2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest src.mov` |
| Odd size | `testsrc2=size=853x479` …  |
| Audio only | `-f lavfi -i sine=frequency=440:duration=2 -c:a flac src.flac` (also WAV 24-bit, 5.1 via `-ac 6`) |
| Video only | `-an` variant |
| Transparent GIF | `-f lavfi -i "color=c=black@0.0:s=64x64:d=1,format=rgba"` … `src.gif` |
| Raster images | made in-process with Core Graphics + ImageIO (PNG with alpha, JPEG with EXIF orientation, HEIC, TIFF 16-bit). No ffmpeg needed. |

VERIFIED: the A/V fixture above, then `-c:v libvpx-vp9 -b:v 0 -crf 34 -deadline realtime -cpu-used 8 -c:a libopus out.webm`, then `ffprobe -show_entries stream=codec_name:format=format_name,duration -of json` returns `vp9, opus`, `matroska,webm`, 2.013 s.

We assert properties, never bytes: container, codecs, dimensions, duration ±1 frame (video) or ±20 ms (audio), channel count, alpha kept, AVFoundation `isPlayable` for MP4/MOV outputs, no partial file left beside the source, and output named per `OutputNamer`. The hostile fixtures (HLS playlist renamed to `.mp4`, ffconcat renamed to `.mkv`) must be refused before ffmpeg opens them (10 §8.9 challenge).

Homebrew ffmpeg 8.1.2 differs from our vendored build: it has x265, libvmaf and openssl, and it keeps the native `opus`/`vorbis` encoders. Integration tests therefore gate on `CapabilityProbe` results, not on version strings. Once `Vendor/out` exists, CI runs them against the vendored build only.

### 6.5 Runtime and trigger tests

| Subject | Method |
|---|---|
| Cancellation | Spawn `/bin/sleep 30` through `SubprocessRunner`, cancel the task, and assert the process group is gone within 500 ms |
| Staging and publication | Inject a failure after staging; assert the destination is untouched and the staging directory is removed. Collision loop with `RENAME_EXCL`. |
| Lanes | Fake engines with controlled latency; assert lane width is honoured; memory-pressure `.warning` halves the width |
| Orphan reaper | Write a PID file for a dead PID; assert cleanup on launch |
| Trigger | Feed the JSON traces in `Fixtures/traces/` (recorded with a Debug "Record trigger trace" menu item) through `TriggerMachine`, and assert the effect lists. Cases: Finder drag + ⇧ tap, ⌘ held at drag start (ignored), double tap closes, mode switch ⇧→⌘, extra modifiers rejected, 40 ms debounce, button-up resets |
| Drop operation mask | Pure function `preferredOperation(mask)` returns the first of `.copy, .generic, .link, .move` that's present (15 C-8) |

Git LFS waits until the real-world corpus arrives (Phase 2). Install `git-lfs` at that point.

### 6.6 UI and E2E: what is automated

Synthetic cross-app drags need `CGEventPost` from a process with **Accessibility** trust. Granting that on hosted CI is impossible (TCC can't be preconfigured on hosted runners) and on dev Macs it's undesirable. So the automated suite **bypasses the trigger** and starts the wheel directly.

| Flow | Automated? | How |
|---|---|---|
| Trigger state machine | yes | trace replay (§6.5) |
| Wheel layout, hit-testing, edge-of-screen placement | yes | pure `WheelGeometry` tests; Solid-theme `ImageRenderer` snapshots (glass can't be rendered offscreen) |
| Wheel → slice → job → output beside source | yes | XCUITest launches with `-UITestFixture <dir> -UITestMode convert`. The app opens the wheel in keyboard mode with those files. The test selects a slice by accessibility identifier (`wheel.slice.<ext>`) and asserts the output file and the result card. |
| HUD, result card, Undo, Settings, onboarding | yes | XCUITest |
| Actions: Copy, Copy Path | yes | XCUITest + pasteboard assert |
| Actions: AirDrop, Move panel, Terminal | partial | XCUITest asserts that the sharing service or panel opens; the rest is manual |
| Real Finder drag + modifier tap → wheel | **no** (manual) | §6.7. Optional later: a self-hosted Mac with an Accessibility-trusted CGEvent harness (14 §5.3) |
| Promise drags (Mail, Photos, Safari) | no | manual, spike P-T5 |
| Latency p95 ≤ 16 ms | partial | `OSSignposter` intervals recorded during manual QA and in the nightly run on the self-hosted Mac |

UI-test hooks are compiled only under `#if DEBUG` and read launch arguments. Release builds ignore them (asserted by a unit test on the Release-configured argument parser).

### 6.7 Manual QA matrix (per release; Phase 1 baseline)

| Source | ⇧ convert | ⌘ tools | ⌃ actions | Held at release | 2 displays | Full-screen Space |
|---|---|---|---|---|---|---|
| Finder window | ☐ | ☐ | ☐ | ☐ (P-T6) | ☐ | ☐ |
| Desktop | ☐ | ☐ | ☐ | ☐ | ☐ | — |
| Mail attachment (promise) | ☐ | ☐ | ☐ | ☐ | — | — |
| Safari / Chrome image | ☐ | — | ☐ | ☐ | — | — |
| Photos | ☐ | — | ☐ | — | — | — |
| VS Code (Electron) | ☐ | ☐ | ☐ | — | — | — |
| With Dropover/Yoink running | ☐ | — | — | — | — | — |

Each cell checks: wheel appears at the cursor, slices match the selection, a drop on a slice writes the output beside the original (or to Downloads for promises), a drop on the hub bounces back, a re-tap closes the wheel, the source is never moved, and there are no permission prompts beyond TCC folder prompts. Record the OS build, the display refresh rate and the signpost p95.

### 6.8 Coverage

```bash
source Scripts/env.sh
cd Packages/ZivletKit
swift test --enable-code-coverage --skip IntegrationTests      # integration counted separately
BIN=$(swift build --show-bin-path)                             # VERIFIED: .build/out/Products/Debug with Swift 6.4
PROF="$BIN/codecov/default.profdata"
OBJS=(); for t in "$BIN"/*Tests.xctest; do OBJS+=(-object "$t/Contents/MacOS/$(basename "$t" .xctest)"); done
xcrun llvm-cov report "${OBJS[@]}" -instr-profile "$PROF" \
  -ignore-filename-regex '(\.build|Tests|ZivletUI|ZivletWheel/Views|AppKitSampler)'
xcrun llvm-cov export -summary-only "${OBJS[@]}" -instr-profile "$PROF" \
  -ignore-filename-regex '(\.build|Tests|ZivletUI|ZivletWheel/Views|AppKitSampler)' > coverage.json
```

- VERIFIED (two test targets): with Swift 6.4, SwiftPM writes one `<Target>Tests.xctest` per test target, and `llvm-cov` merges them, which is why there are several `-object` arguments. The profile lands at `<bin>/codecov/default.profdata`, and `swift test --show-codecov-path` prints the merged JSON path.
- `Scripts/coverage.sh` wraps the commands above. It parses `coverage.json` per module directory and fails if any gated module (§4.1) is below **80 % line coverage**.
- Exclusions are only the view and AppKit layers listed in the regex. Adding an exclusion needs a PR that explains it.

---

## 7. FFmpeg: development and vendoring

### 7.1 `EngineLocator` resolution order

| Order | Source | Build configs | Integrity check |
|---|---|---|---|
| 1 | `Bundle.main.bundleURL/Contents/Helpers/{ffmpeg,ffprobe}` | all | Release: `SecStaticCodeCheckValidity` with requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"` and identifier `app.zivlet.ffmpeg`. Debug and ad-hoc: signature present and valid. |
| 2 | `ZIVLET_ENGINE_DIR` env var (directory holding `ffmpeg`, `ffprobe`) | Debug only (`ZIVLET_ALLOW_SYSTEM_ENGINES`) | executable bit, regular file, not world-writable |
| 3 | `/opt/homebrew/bin/{ffmpeg,ffprobe}` | Debug only | same as 2. Logs a `.notice` "using system ffmpeg (dev)" |
| — | none found | — | `CapabilityProbe` marks media routes unavailable. The wheel hides them and Settings shows the reason. |

- Release builds compile without orders 2–3 (the flag isn't defined), so they can't fall back to Homebrew (10 §8.9).
- A unit test asserts the Release configuration resolves only order 1.
- Phase 0 develops against Homebrew ffmpeg 8.1.2. Phase 1 embeds the vendored build, and from then on CI runs integration tests only against the vendored build.

### 7.2 Vendored build

| File | Role |
|---|---|
| `Vendor/versions.lock` | FFmpeg 9.0.2 (fallback 8.1.3), x264 @ b35605ac, libvpx 1.17.0, SVT-AV1 4.2.0, dav1d 1.5.4, Opus 1.6.1, libogg 1.3.6, libvorbis 1.3.7, LAME 3.100, libwebp 1.6.0, zimg 3.0.6. Each with URL + SHA-256 (11 §6.2). |
| `Vendor/build-media.sh` | Fetch and verify SHA-256 → static deps → FFmpeg shared libs (`--enable-gpl --enable-version3 --disable-network --disable-devices --disable-autodetect --disable-encoder=opus,vorbis --disable-demuxer=hls,dash,webm_dash_manifest,sdp,rtsp,rtp`, `--install-name-dir=@rpath`, rpath `@executable_path/../Frameworks`) → dSYMs → `strip -x`. Uses `PKG_CONFIG_LIBDIR` set only to our prefix, `SOURCE_DATE_EPOCH`, `-ffile-prefix-map`, `MACOSX_DEPLOYMENT_TARGET=26.0`. |
| `Vendor/verify-media.sh` | No `nonfree`; `-L` says version 3; `otool -L` deps are only `@rpath`/`/usr/lib`/`/System`; `lipo` arm64; `minos 26.0`; no `/Users/` path leaks; required encoder list (11 §6.4). Sonames are read from the build, never hard-coded (15 C-1). |
| `Vendor/build-native.sh` | libwebp → `CWebP.xcframework` (Phase 1). libarchive and qpdf arrive in Phase 2. |
| `Scripts/embed-helpers.sh` | Xcode post-build step. If `Vendor/out` exists: copy `ffmpeg`/`ffprobe` → `Contents/Helpers/`, `libav*.dylib` → `Contents/Frameworks/`, then sign inside-out with the active identity (`-` in dev). Otherwise it does nothing and logs that Homebrew will be used (Debug only). Release fails if `Vendor/out` is missing. |

Output: `Vendor/out/{bin,lib,dSYMs}` (gitignored), plus `zivlet-vendor-<lockhash>.tar.zst` and `zivlet-vendor-src-<lockhash>.tar.xz` (the GPL source) as CI artifacts. App builds download the artifact by lock hash; no app build compiles FFmpeg.

---

## 8. Signing

### 8.1 Development (until O-11 provides a Developer ID)

| Item | Setting / behaviour |
|---|---|
| Identity | ad-hoc `-`, hardened runtime forced in Debug (§3.2) |
| Helpers | `codesign -f -s - -o runtime -i app.zivlet.ffmpeg <file>`, inside-out: dylibs → helpers → app |
| TCC side effect | An ad-hoc designated requirement is the cdhash, so every rebuild counts as a new app and folder prompts (Desktop, Documents, Downloads) come back. Optional fix: a self-signed "Zivlet Dev" code-signing certificate in the login keychain gives a stable requirement. **TO VERIFY** in P-T1. |
| Library validation | Applies to the vendored ffmpeg loading ad-hoc `libav*` under hardened runtime. **TO VERIFY** in spike M-2 (Homebrew ffmpeg runs unsigned-by-us as a child process, so Phase 0 isn't affected). |
| Distribution | Ad-hoc builds go only to the owner's own Macs. Nothing public before O-11 and O-12. |

### 8.2 Release (Developer ID)

| Rule | Detail |
|---|---|
| Order | `sign-helpers.sh` signs inside-out: dylibs → helpers → frameworks (Sparkle) → app. Always `--options runtime --timestamp`, with explicit `-i` identifiers. |
| Never | `codesign --deep` for signing; non-Mach-O files in `Contents/Helpers` (15 C-2); `get-task-allow` in Release |
| Verify | `verify-signatures.sh` walks **every** Mach-O in the bundle and checks `flags` include `runtime`, a secure timestamp, the Team ID and the entitlements allow-list. Then `codesign --verify --strict --deep` (verification only) and `spctl -a -vvv`. |
| Code Sign On Copy | Not trusted until spike M-2. The script is authoritative. |
| Secrets | `DEVID_P12_BASE64`, `DEVID_P12_PASSWORD`, `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`. Only in the protected `release` environment; forks never sign. The owner keeps an offline backup of the EdDSA key. |

---

## 9. CI (GitHub Actions)

### 9.1 Runners

| Runner | Use | Note |
|---|---|---|
| `macos-26` (hosted, arm64) | build, unit, goldens, integration subset, UI smoke | The hosted image ships Xcode 26.6 as of 2026-10-20 (10 §8.10). **TO VERIFY** that Xcode 27 is on the image. Each job runs `ls /Applications/Xcode_27*.app` and fails with a clear message if it's absent. Until then, route jobs to the self-hosted label. |
| self-hosted `[self-hosted, macOS, ARM64, xcode27]` | clean-OS jobs (Tart 26.0 / 26.x / 27.x images), `spctl` first launch, Sparkle N-1 → N, G-0, real-drag harness later | One Mac mini, Phase 0 (spike P-CI, 15 C-10). Hosted runners can't nest VMs. |

### 9.2 Workflows

| Workflow | Trigger | Jobs |
|---|---|---|
| `ci.yml` | PR, push to `main` | `lint` (swift format, `lint.sh` size/print/import rules, commit-message check) → `test` (`swift test --enable-code-coverage --skip IntegrationTests`, `coverage.sh` gate) → `integration` (ffmpeg from the vendor artifact; Phase 0 uses `brew install ffmpeg` with `ZIVLET_ENGINE_DIR`) → `build` (`xcodegen generate`; `xcodebuild build CODE_SIGNING_ALLOWED=NO`) → `uitest` smoke (ad-hoc signed) |
| `vendor.yml` | changes to `Vendor/**` | `build-media.sh`, `verify-media.sh`, `build-native.sh`, build twice and diff the hashes; upload artifacts keyed by lock hash |
| `nightly.yml` | cron 03:00 UTC | full pair matrix (Phase 1: 153 pairs), hostile corpus, UI suite, signpost run on self-hosted |
| `release.yml` | tag `v*`, `release` environment with a required reviewer | §10 |

Outline of `ci.yml`:

```yaml
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
env: { DEVELOPER_DIR: /Applications/Xcode_27.0.app/Contents/Developer, ZIVLET_REQUIRE_ENGINES: "1" }
jobs:
  test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: test -d "$DEVELOPER_DIR" || { echo "Xcode 27 missing on runner"; exit 1; }
      - uses: actions/cache@v4
        with: { path: Packages/ZivletKit/.build, key: spm-${{ hashFiles('Packages/ZivletKit/Package.resolved') }} }
      - run: Scripts/lint.sh
      - run: Scripts/test.sh --coverage          # swift test + coverage.sh gate (80 %)
      - uses: actions/upload-artifact@v4
        with: { name: coverage, path: Packages/ZivletKit/coverage.json }
  build:
    needs: test
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen && xcodegen generate
      - run: xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Release build CODE_SIGNING_ALLOWED=NO
```

Required checks on `main`: `lint`, `test`, `integration`, `build`. Coverage, licence and size gates must pass, with no override label.

---

## 10. Release process (outline)

| Step | Command / script | Gate |
|---|---|---|
| 1. Freeze | Tag `vX.Y.Z` on `main` (or `vX.Y.Z-beta.N`). `CURRENT_PROJECT_VERSION` = CI run number. | nightly green on that commit |
| 2. Archive | `xcodebuild archive -scheme Zivlet -configuration Release ARCHS=arm64` | — |
| 3. Embed + sign helpers | `embed-helpers.sh`, `sign-helpers.sh` | — |
| 4. Export | `xcodebuild -exportArchive -exportOptionsPlist Config/ExportOptions.plist` | — |
| 5. Verify | `verify-signatures.sh` | signature gate |
| 6. Notarize app | `ditto -c -k --keepParent`, `xcrun notarytool submit --wait`, `xcrun stapler staple` | accepted |
| 7. DMG | `make-dmg.sh` (APFS, signed) → notarize → staple → `spctl -a -t install` | — |
| 8. Clean-VM smoke | self-hosted Tart 26.0 image: first launch, one pair per engine | pass |
| 9. Size | `size-gate.sh` | ≤ 85 MB installed / ≤ 40 MB DMG hard, warn above 70 / 32 (O-3) |
| 10. Source + SBOM | `source-bundle.sh` → `Zivlet-<ver>-source.tar.xz` (app source, vendored tarballs, patches, `versions.lock`, scripts, Xcode/CLT versions); CycloneDX SBOM | licence gate (10 §10.3) |
| 11. Appcast | `appcast.sh` (`generate_appcast --ed-key-file - --maximum-deltas 3`, `--channel beta` for betas) | — |
| 12. Publish | `gh release upload` (DMG, deltas, source, SBOM, dSYMs); push `appcast.xml` to `gh-pages` | — |

Phase 0 exit runs steps 2–12 once on a "hello" build with ffmpeg embedded, plus a Sparkle N-1 → N update on the clean VM. Before O-11 only steps 2–5 (ad-hoc) and 9–10 can run.

---

## 11. Git conventions

| Item | Rule |
|---|---|
| Commit format | `<type>(<scope>): <description>`. Types: `feat fix refactor docs test chore perf ci`. Scope = module or area: `core`, `enginekit`, `media`, `image`, `runtime`, `trigger`, `wheel`, `ui`, `app`, `vendor`, `ci`, `release`. |
| Examples | `feat(trigger): add pure TriggerMachine with trace replay` · `fix(media): force libopus for WebM audio` · `test(runtime): cover cancel kills process group` |
| Trailers | `Signed-off-by:` required (DCO, O-2; `git commit -s`). **No `Co-Authored-By:`** trailers. The `commit-msg` hook and the CI check reject them. |
| Branches | `main` is protected. Work happens on `feat/…`, `fix/…`, `chore/…`. |
| Merge | Squash merge; the PR title is the conventional commit. Linear history. |
| PR template | Summary, test plan, a coverage delta, a "no reference-app / Open-Tangerine material" checkbox, and a licence row for any new dependency |
| Tags | `vMAJOR.MINOR.PATCH[-beta.N]`, annotated, created by the release owner only |
| Hooks | `Scripts/hooks/commit-msg` (format + no Co-Authored-By + requires Signed-off-by); `pre-commit` (`swift format lint` on staged files, `lint.sh --staged`) |
| Never committed | generated `Zivlet.xcodeproj`, `Vendor/out`, certificates, keys, `.profdata` |

---

## 12. Definition of done (every PR)

- [ ] Test written first and seen failing; now passing (`Scripts/test.sh`).
- [ ] Gated modules ≥ 80 % line coverage (`Scripts/coverage.sh`).
- [ ] `Scripts/lint.sh` clean: format, ≤ 800 lines per file, no `print`, import rules.
- [ ] Functions < 50 lines, nesting ≤ 3, no magic numbers, no new `var` in model types.
- [ ] Errors typed and surfaced; inputs validated at the boundary that was touched.
- [ ] Logging uses the right `Logger` category with `.private` paths.
- [ ] `xcodegen generate && xcodebuild build` succeeds with warnings as errors.
- [ ] Conventional commit title, `Signed-off-by`, no `Co-Authored-By`.

## 13. Open items for this handbook

| ID | Item | Resolve by |
|---|---|---|
| H-1 | Xcode 27 availability on hosted `macos-26` images | before the first CI run (Phase 0) |
| H-2 | Stable dev signing identity to stop TCC re-prompts on each rebuild | P-T1 |
| H-3 | Library validation for ad-hoc vendored dylibs under hardened runtime | M-2 |
| H-4 | Whether `swift format`'s rule set covers the nesting limit or `lint.sh` needs its own check | Phase 0 skeleton |
| H-5 | Bundle id and repository name (O-10, O-12) before any public artifact | owner |
