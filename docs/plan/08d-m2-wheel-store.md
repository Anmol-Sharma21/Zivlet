# 08d — M2 task 7: accent palette, themes, feedback, WheelStore

Part of [08-implementation-plan-m2](08-implementation-plan-m2.md). Conventions: index §4. Commands run from
`$REPO/Packages/ZivletKit` with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

---

## Task 7 — Appearance, feedback and the observable store (P0-42, model side)

| Field | Value |
|---|---|
| Goal | Everything the views read, as testable values and one `@Observable` store. `RGB` + `AccentPalette`: one accent token with light (+24 % white) and dark (saturation × 1.12 capped, brightness × 0.74) stops and a label colour chosen by contrast. `WheelTheme`: Glass or Solid, Solid forced by Reduce Transparency or Increase Contrast. `ToneSynth`: the tick as a WAV built in code. `SystemWheelFeedback`: haptic patterns and the tick behind the 35 ms gate, silent when UI sounds are off. `WheelStore`: holds the immutable `WheelModel`, replaces it only when a hit changes the highlight, fires one feedback per new slot, and shows a 1.2 s reject notice |
| 05 rows | P0-42 (model side); 01-prd FR-22, FR-26 |
| Sources | 03a §2.7 (feedback table, accent recipe, tick rules), 14 §2.4 (`.alignment` at `.now`, `.levelChange`, `.generic`), 01-prd FR-22, FR-26, index D-M2-4, D-M2-5 |

| Event | Store call | Feedback |
|---|---|---|
| Pointer enters a new slot | `pointer(.slot(i))` | `.alignment` haptic + tick (≤ 1 per 35 ms) |
| Pointer to hub / outside / same slot | `pointer(.hub)` | none |
| Mode switch | `switchTo(_:emptyMessage:)` | `.levelChange` |
| Reject (T12) | `reject(message:)` | `.generic`, shake (`rejectCount`), pill 1.2 s |
| Drop accepted | `dropAccepted()` | `.generic` |

**Files**

| Action | Path (under `Packages/ZivletKit/`) |
|---|---|
| create | `Sources/ZivletWheel/AccentPalette.swift` (`RGB`, `AccentPalette`) |
| create | `Sources/ZivletWheel/WheelAppearance.swift` (`WheelTheme`, `WheelAppearance`, `WheelTiming`) |
| create | `Sources/ZivletWheel/ToneSynth.swift`, `Sources/ZivletWheel/WheelFeedback.swift` (`WheelFeedback`, `SystemWheelFeedback`, `TickSound`) |
| create | `Sources/ZivletWheel/WheelStore.swift` |
| create | `Tests/ZivletWheelTests/WheelFakes.swift` (fakes, fixtures, `eventually`), `AppearanceTests.swift`, `WheelStoreTests.swift` |
| delete | `Sources/ZivletWheel/ZivletWheelPlaceholder.swift`, `Tests/ZivletWheelTests/ZivletWheelSmokeTests.swift` |

### 7.1 Failing tests first

`WheelFakes.swift` is shared by Tasks 7–10. `eventually` polls a main-actor condition instead of sleeping a fixed
time: in the prototype a fixed 80 ms sleep was flaky while the render tests ran in parallel.

`Packages/ZivletKit/Tests/ZivletWheelTests/WheelFakes.swift`:

```swift
import AppKit
import ZivletCore
import ZivletWheelCore

@testable import ZivletWheel

/// Counts feedback calls instead of buzzing the trackpad.
final class FakeFeedback: WheelFeedback {
    private(set) var events: [String] = []
    func highlightChanged() { events.append("highlight") }
    func modeSwitched() { events.append("switch") }
    func rejected() { events.append("reject") }
    func dropAccepted() { events.append("drop") }
}

final class FakeHaptics: NSObject, NSHapticFeedbackPerformer {
    private(set) var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []
    func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern,
        performanceTime: NSHapticFeedbackManager.PerformanceTime
    ) { patterns.append(pattern) }
}

enum Fixtures {
    static let builder = SliceBuilder()

    static func model(_ mode: WheelMode = .convert, _ formats: [FormatID] = [.png]) -> WheelModel {
        let items = formats.map { SelectionItem($0) }
        return WheelModel(mode: mode, content: builder.content(for: mode, items: items), idleHubLabel: "photo.png")
    }

    static let appearance = WheelAppearance(
        theme: .solid, palette: AccentPalette(base: RGB(r: 0.2, g: 0.5, b: 0.9)), reduceMotion: true)
}

extension Fixtures {
    /// A convert wheel with `count` PNG-labelled slices (1…12), for layout and render tests.
    static func slices(_ count: Int, highlighted: Int? = nil) -> WheelModel {
        let slices = (0..<count).map { index in
            WheelSlice(id: "convert.\(index)", label: "F\(index)", symbolName: nil, target: .convert(.png), badge: nil)
        }
        return WheelModel(
            mode: .convert, content: .slices(slices), idleHubLabel: "2 PNG FILES", highlighted: highlighted)
    }
}

/// Polls a main-actor condition every 10 ms for up to `timeout`; parallel render tests can delay timers.
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
```

`Packages/ZivletKit/Tests/ZivletWheelTests/AppearanceTests.swift`:

```swift
import Foundation
import Testing

@testable import ZivletWheel

@Suite("Wheel appearance: accent palette, theme, tick tone (03a §2.7)")
struct AppearanceTests {
    func close(_ a: RGB, _ b: RGB) -> Bool { abs(a.r - b.r) < 1e-6 && abs(a.g - b.g) < 1e-6 && abs(a.b - b.b) < 1e-6 }

    @Test func paletteDerivesLightAndDarkFromOneBase() {
        let palette = AccentPalette(base: RGB(r: 1, g: 0.5, b: 0))
        #expect(close(palette.light, RGB(r: 1, g: 0.62, b: 0.24)))
        #expect(close(palette.dark, RGB(r: 0.74, g: 0.37, b: 0)))
    }

    @Test func darkStopRaisesSaturationButCapsIt() {
        let muted = AccentPalette(base: RGB(r: 0.5, g: 0.4, b: 0.4))
        let (_, s, b) = muted.dark.hsb
        #expect(abs(s - 0.2 * 1.12) < 1e-6 && abs(b - 0.37) < 1e-6)
        let (_, capped, _) = AccentPalette(base: RGB(r: 0, g: 0.48, b: 1)).dark.hsb
        #expect(capped == 1)
    }

    @Test func hsbRoundTrips() {
        for colour in [RGB(r: 0.2, g: 0.6, b: 0.4), RGB(r: 0.9, g: 0.1, b: 0.7), RGB(r: 0.5, g: 0.5, b: 0.5)] {
            let (h, s, b) = colour.hsb
            #expect(close(RGB(hue: h, saturation: s, brightness: b), colour))
        }
    }

    @Test func labelOnAccentPicksTheHigherContrast() {
        #expect(AccentPalette(base: RGB(r: 0.1, g: 0.2, b: 0.5)).labelOnAccent == .white)
        #expect(AccentPalette(base: RGB(r: 1, g: 0.85, b: 0.3)).labelOnAccent == .black)
        #expect(abs(RGB.white.contrast(with: .black) - 21) < 1e-9)
    }

    @Test func componentsAreClamped() {
        #expect(RGB(r: 2, g: -1, b: 0.5) == RGB(r: 1, g: 0, b: 0.5))
    }

    @Test(arguments: [
        (WheelTheme.glass, false, false, WheelTheme.glass), (.glass, true, false, .solid),
        (.glass, false, true, .solid), (.solid, false, false, .solid),
    ])
    func solidReplacesGlassUnderAccessibilitySettings(
        preference: WheelTheme, reduceTransparency: Bool, increaseContrast: Bool, expected: WheelTheme
    ) {
        let theme = WheelTheme.resolve(
            preference: preference, reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
        #expect(theme == expected)
    }

    @Test func themePreferenceReadsDefaultsStrings() {
        #expect(WheelTheme(preference: "solid") == .solid)
        #expect(WheelTheme(preference: nil) == .glass && WheelTheme(preference: "chrome") == .glass)
    }

    @Test func tickToneIsAShortMonoWAV() throws {
        let wav = ToneSynth.wav(duration: .milliseconds(24))
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav[8..<16], as: UTF8.self) == "WAVEfmt ")
        let samples = 48_000 * 24 / 1_000
        #expect(wav.count == 44 + samples * 2)
        let pcm = wav.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        let peak = try #require(pcm.map { abs(Int($0)) }.max())
        #expect(peak > 1_000 && peak <= Int(0.2 * 32_767))
        #expect(abs(Int(pcm[0])) < 100 && abs(Int(pcm[samples - 1])) < 300)
    }
}
```

`Packages/ZivletKit/Tests/ZivletWheelTests/WheelStoreTests.swift`:

```swift
import AppKit
import ZivletCore
import ZivletWheelCore
import Testing

@testable import ZivletWheel

@Suite("Wheel store: highlight, feedback, notices (03a §2.4, §2.7)")
struct WheelStoreTests {
    let feedback = FakeFeedback()

    func store(notice: Duration = .milliseconds(30)) -> WheelStore {
        WheelStore(feedback: feedback, noticeDuration: notice)
    }

    @Test func presentShowsTheModelCollapsedUntilExpanded() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        #expect(s.model?.mode == .convert && s.theme == .solid && !s.isExpanded)
        s.expand()
        #expect(s.isExpanded)
    }

    @Test func highlightChangeFiresOneFeedbackPerNewSlot() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.pointer(.slot(1))
        s.pointer(.slot(1))
        s.pointer(.hub)
        s.pointer(.slot(2))
        #expect(feedback.events == ["highlight", "highlight"])
        #expect(s.model?.highlighted == 2)
    }

    @Test func pointerWithoutAWheelIsIgnored() {
        let s = store()
        s.pointer(.slot(0))
        #expect(s.model == nil && feedback.events.isEmpty)
    }

    @Test func switchReplacesTheModelAndPlaysTheLevelChange() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.pointer(.slot(0))
        s.switchTo(Fixtures.model(.actions), emptyMessage: nil)
        #expect(s.model?.mode == .actions && s.model?.highlighted == nil)
        #expect(feedback.events == ["highlight", "switch"])
    }

    @Test func rejectShowsANoticeThatClearsItself() async throws {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.reject(message: "No tools for SRT files")
        #expect(s.pillText == "No tools for SRT files" && s.rejectCount == 1)
        #expect(feedback.events == ["reject"])
        #expect(try await eventually { s.pillText == nil })
    }

    @Test func emptyWheelShowsItsReasonInThePill() {
        let s = store()
        let empty = WheelModel(mode: .tools, content: .empty(.noTools(.srt)), idleHubLabel: "a.srt")
        s.present(empty, emptyMessage: "No tools for SRT files", appearance: Fixtures.appearance)
        #expect(s.pillText == "No tools for SRT files")
    }

    @Test func dropAcceptedAndDismissResetEverything() {
        let s = store()
        s.present(Fixtures.model(), emptyMessage: nil, appearance: Fixtures.appearance)
        s.expand()
        s.dropAccepted()
        s.dismiss()
        #expect(s.model == nil && !s.isExpanded && s.pillText == nil)
        #expect(feedback.events == ["drop"])
    }

    @Test func systemFeedbackMapsEventsToHapticPatterns() {
        let haptics = FakeHaptics()
        let ticks = TickLog()
        let system = SystemWheelFeedback(performer: haptics, tick: TickSound(isEnabled: true, play: ticks.play))
        system.highlightChanged()
        system.modeSwitched()
        system.rejected()
        system.dropAccepted()
        #expect(haptics.patterns == [.alignment, .levelChange, .generic, .generic])
        #expect(ticks.count == 1)
    }

    @Test func tickSoundIsThrottledAndSilentWhenDisabled() {
        let ticks = TickLog()
        let clock = ManualClock()
        let sound = TickSound(isEnabled: true, now: clock.read, play: ticks.play)
        sound.play()
        clock.advance(.milliseconds(10))
        sound.play()
        clock.advance(.milliseconds(40))
        sound.play()
        #expect(ticks.count == 2)
        let muted = TickSound(isEnabled: false, play: ticks.play)
        muted.play()
        #expect(ticks.count == 2)
    }

    @Test func realTickSoundLoadsTheSynthesizedTone() {
        let sound = TickSound(isEnabled: true)
        #expect(sound.isLoaded)
    }
}

final class TickLog {
    private(set) var count = 0
    func play() { count += 1 }
}

final class ManualClock {
    private var value: Duration = .seconds(1)
    func read() -> Duration { value }
    func advance(_ by: Duration) { value += by }
}
```

### 7.2 Run, expect failure

`swift test --filter ZivletWheelTests` → `error: cannot find 'AccentPalette' in scope` (also `RGB`,
`WheelAppearance`, `WheelFeedback`).

### 7.3 Implement (complete)

`Packages/ZivletKit/Sources/ZivletWheel/AccentPalette.swift`:

```swift
import AppKit
import SwiftUI

/// sRGB colour, components clamped to 0…1. Pure maths so the palette rules are testable.
public struct RGB: Sendable, Equatable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let black = RGB(r: 0, g: 0, b: 0)

    /// Hue in 0…1 (fraction of a turn).
    public init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - chroma
        let (r, g, b): (Double, Double, Double) =
            switch Int(sector) {
            case 0: (chroma, x, 0)
            case 1: (x, chroma, 0)
            case 2: (0, chroma, x)
            case 3: (0, x, chroma)
            case 4: (x, 0, chroma)
            default: (chroma, 0, x)
            }
        self.init(r: r + m, g: g + m, b: b + m)
    }

    /// Converts any colour to sRGB; colours without RGB components fall back to mid grey.
    public init(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            self.init(r: 0.5, g: 0.5, b: 0.5)
            return
        }
        self.init(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }

    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(r, g, b)
        let delta = high - min(r, g, b)
        guard delta > 0 else { return (0, 0, high) }
        let raw: Double =
            if high == r { ((g - b) / delta).truncatingRemainder(dividingBy: 6) } else if high == g {
                (b - r) / delta + 2
            } else { (r - g) / delta + 4 }
        let hue = raw / 6
        return (hue < 0 ? hue + 1 : hue, delta / high, high)
    }

    public func mixed(with other: RGB, amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    public func contrast(with other: RGB) -> Double {
        let (light, dark) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

/// One accent token and its derived stops (03a §2.7): light = +24 % white; dark = saturation × 1.12 (capped),
/// brightness × 0.74. The base hue is Zivlet's choice: the user's system accent colour (08 index D-M2-4).
public struct AccentPalette: Sendable, Equatable {
    public let base: RGB
    public let light: RGB
    public let dark: RGB

    public init(base: RGB) {
        self.base = base
        light = base.mixed(with: .white, amount: 0.24)
        let (h, s, b) = base.hsb
        dark = RGB(hue: h, saturation: min(s * 1.12, 1), brightness: b * 0.74)
    }

    public static var system: AccentPalette { AccentPalette(base: RGB(NSColor.controlAccentColor)) }

    /// White or black, whichever contrasts more with the base (01-prd FR-26 asks ≥ 4.5:1 where reachable).
    public var labelOnAccent: RGB { base.contrast(with: .white) >= base.contrast(with: .black) ? .white : .black }
}
```

`WheelAppearance.current()` reads the `ZivletWheelTheme` default, so `-ZivletWheelTheme solid` on the command line
selects Solid (launch arguments land in the argument domain of `UserDefaults`).

`Packages/ZivletKit/Sources/ZivletWheel/WheelAppearance.swift`:

```swift
import AppKit

/// Glass (Liquid Glass petals) or Solid (opaque, high contrast) (01-prd FR-26).
public enum WheelTheme: String, Sendable, CaseIterable {
    case glass, solid

    /// Defaults value of `ZivletWheelTheme`; anything unknown means glass.
    public init(preference: String?) {
        self = preference.flatMap(WheelTheme.init(rawValue:)) ?? .glass
    }

    /// Solid is forced under Reduce Transparency or Increase Contrast (03a §2.7).
    public static func resolve(preference: WheelTheme, reduceTransparency: Bool, increaseContrast: Bool) -> WheelTheme {
        reduceTransparency || increaseContrast ? .solid : preference
    }
}

/// Everything visual that is decided once per show.
public struct WheelAppearance: Sendable, Equatable {
    public static let themeKey = "ZivletWheelTheme"

    public let theme: WheelTheme
    public let palette: AccentPalette
    public let reduceMotion: Bool

    public init(theme: WheelTheme, palette: AccentPalette, reduceMotion: Bool) {
        self.theme = theme
        self.palette = palette
        self.reduceMotion = reduceMotion
    }

    /// Reads the theme preference (launch arguments `-ZivletWheelTheme solid` land here too) and the system
    /// accessibility switches.
    public static func current(defaults: UserDefaults = .standard) -> WheelAppearance {
        let workspace = NSWorkspace.shared
        let theme = WheelTheme.resolve(
            preference: WheelTheme(preference: defaults.string(forKey: themeKey)),
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
        return WheelAppearance(
            theme: theme, palette: .system, reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
    }
}

/// Animation numbers (03a §2.7, 05 P0-42), in one place.
enum WheelTiming {
    static let fadeIn = 0.07
    static let introScale = 0.45
    static let intro = 0.20
    static let labelsDelay = 0.05
    static let labels = 0.10
    static let highlight = 0.12
    static let morph = 0.28
    static let morphBounce = 0.15
    static let shake = 0.24
    static let hide = 0.08
    static let reducedMotionFade = 0.08
}
```

`Packages/ZivletKit/Sources/ZivletWheel/ToneSynth.swift`:

```swift
import Foundation

/// The highlight tick, synthesized in code (no bundled sample): a short sine burst with a 1 ms attack, a fast
/// exponential decay and a 1 ms fade-out, as 16-bit mono PCM in a WAV container.
public enum ToneSynth {
    public static func wav(
        frequency: Double = 1_318.5, duration: Duration = .milliseconds(24), sampleRate: Int = 48_000,
        amplitude: Double = 0.18
    ) -> Data {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let count = Int(seconds * Double(sampleRate))
        let tail = Double(sampleRate) / 1_000
        let samples = (0..<count).map { index -> Int16 in
            let t = Double(index) / Double(sampleRate)
            let envelope = min(1, t / 0.001) * exp(-t / 0.006) * min(1, Double(count - 1 - index) / tail)
            return Int16((sin(2 * .pi * frequency * t) * amplitude * envelope * 32_767).rounded())
        }
        return header(sampleCount: count, sampleRate: sampleRate)
            + samples.reduce(into: Data()) { data, sample in
                withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) }
            }
    }

    private static func header(sampleCount: Int, sampleRate: Int) -> Data {
        let dataSize = UInt32(sampleCount * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // PCM
        append(UInt16(1))  // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // byte rate
        append(UInt16(2))  // block align
        append(UInt16(16))  // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        return data
    }
}
```

`TickSound.uptime` is `nonisolated`: a main-actor function cannot be stored in the plain `() -> Duration` property
(the compiler reports `converting function value … loses global actor 'MainActor'`). The UI-sound key is confirmed
by spike P-W4.

`Packages/ZivletKit/Sources/ZivletWheel/WheelFeedback.swift`:

```swift
import AppKit
import AudioToolbox
import ZivletWheelCore
import os

/// Haptic and sound feedback for wheel events (03a §2.7). A protocol so the store is testable.
public protocol WheelFeedback: AnyObject {
    func highlightChanged()
    func modeSwitched()
    func rejected()
    func dropAccepted()
}

/// Trackpad haptics plus the synthesized tick on highlight changes (14 §2.4).
public final class SystemWheelFeedback: WheelFeedback {
    private let performer: any NSHapticFeedbackPerformer
    private let tick: TickSound
    private let hapticsEnabled: Bool

    public init(
        performer: any NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer,
        tick: TickSound = TickSound(), hapticsEnabled: Bool = true
    ) {
        self.performer = performer
        self.tick = tick
        self.hapticsEnabled = hapticsEnabled
    }

    public func highlightChanged() {
        haptic(.alignment)
        tick.play()
    }

    public func modeSwitched() { haptic(.levelChange) }
    public func rejected() { haptic(.generic) }
    public func dropAccepted() { haptic(.generic) }

    /// `.now`: the highlight is already a frame behind the pointer (14 §2.4).
    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard hapticsEnabled else { return }
        performer.perform(pattern, performanceTime: .now)
    }
}

/// Plays the tick through System Sound Services: low latency, overlapping, off the main thread. At most one tick per
/// 35 ms (`FeedbackGate`); silent when the system's user-interface sounds are off (spike P-W4 confirms the key).
public final class TickSound {
    public static let uiSoundsKey = "com.apple.sound.uiaudio.enabled"

    let isLoaded: Bool
    private let isEnabled: Bool
    private let now: () -> Duration
    private let player: () -> Void
    private var gate = FeedbackGate()

    public convenience init(isEnabled: Bool = TickSound.systemUISoundsEnabled()) {
        let sound = Self.loadTone()
        self.init(isEnabled: isEnabled, isLoaded: sound != nil) {
            if let sound { AudioServicesPlaySystemSound(sound) }
        }
    }

    init(
        isEnabled: Bool, isLoaded: Bool = true, now: @escaping () -> Duration = TickSound.uptime,
        play: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.now = now
        player = play
    }

    public func play() {
        guard isEnabled else { return }
        let t = now()
        let (admitted, next) = gate.admit(requestedAt: t, now: t)
        gate = next
        if admitted { player() }
    }

    public static func systemUISoundsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: uiSoundsKey) as? Bool ?? true
    }

    nonisolated static func uptime() -> Duration { .seconds(ProcessInfo.processInfo.systemUptime) }

    /// Writes the synthesized tone once to the temporary directory and registers it as a system sound.
    private static func loadTone() -> SystemSoundID? {
        let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "wheel")
        let url = FileManager.default.temporaryDirectory.appending(path: "app.zivlet.tick-v1.wav")
        do {
            try ToneSynth.wav().write(to: url, options: .atomic)
        } catch {
            logger.error("Tick tone not written: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        var sound: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &sound)
        guard status == kAudioServicesNoError else {
            logger.error("Tick tone not registered: OSStatus \(status, privacy: .public)")
            return nil
        }
        return sound
    }
}
```

`Packages/ZivletKit/Sources/ZivletWheel/WheelStore.swift`:

```swift
import Observation
import ZivletWheelCore

/// Observable holder of the immutable `WheelModel` (02 §7.7). It replaces the model only when a hit changes the
/// highlight, so SwiftUI re-renders on slot changes, not on every `draggingUpdated`.
@Observable
public final class WheelStore {
    public private(set) var model: WheelModel?
    public private(set) var appearance = WheelAppearance(
        theme: .glass, palette: AccentPalette(base: RGB(r: 0, g: 0.48, b: 1)), reduceMotion: false)
    public private(set) var isExpanded = false
    /// Bumped on each reject; drives the shake animation.
    public private(set) var rejectCount = 0
    private var notice: String?
    private var emptyMessage: String?

    @ObservationIgnored private let feedback: any WheelFeedback
    @ObservationIgnored private let noticeDuration: Duration
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    public init(feedback: any WheelFeedback, noticeDuration: Duration = .milliseconds(1_200)) {
        self.feedback = feedback
        self.noticeDuration = noticeDuration
    }

    public var theme: WheelTheme { appearance.theme }
    /// Reject notice first, else the empty-state reason.
    public var pillText: String? { notice ?? emptyMessage }

    /// Shows a new wheel collapsed; the on-screen view calls `expandIfPending(presentation)` once it has rendered it
    /// (see 08g: presentation counter, `cancelExpansion()` on hide).
    public func present(_ model: WheelModel, emptyMessage: String?, appearance: WheelAppearance) {
        clearNotice()
        self.model = model
        self.emptyMessage = emptyMessage
        self.appearance = appearance
        isExpanded = false
    }

    public func expand() { isExpanded = true }

    public func pointer(_ hit: HitResult) {
        guard let model else { return }
        let next = model.applying(hit)
        guard next != model else { return }
        self.model = next
        if next.highlighted != nil { feedback.highlightChanged() }
    }

    public func switchTo(_ model: WheelModel, emptyMessage: String?) {
        clearNotice()
        self.model = model
        self.emptyMessage = emptyMessage
        feedback.modeSwitched()
    }

    /// Another wheel refused the items: shake and show why for 1.2 s; the current wheel stays (03a §1.4 T12).
    public func reject(message: String) {
        notice = message
        rejectCount += 1
        feedback.rejected()
        noticeTask?.cancel()
        noticeTask = Task { [weak self, noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    public func dropAccepted() { feedback.dropAccepted() }

    public func dismiss() {
        clearNotice()
        model = nil
        emptyMessage = nil
        isExpanded = false
    }

    private func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }
}
```

Delete the placeholder and the smoke test:

```bash
git rm -q Sources/ZivletWheel/ZivletWheelPlaceholder.swift Tests/ZivletWheelTests/ZivletWheelSmokeTests.swift
```

### 7.4 Verify green

`swift test --filter ZivletWheelTests 2>&1 | grep -E "Test run with|error: "` →
`✔ Test run with 18 tests in 2 suites passed`.

### 7.5 Commit

```bash
git add Packages/ZivletKit/Sources/ZivletWheel Packages/ZivletKit/Tests/ZivletWheelTests
git commit -s -m "feat(wheel): add accent palette, themes, synthesized tick and WheelStore"
```
