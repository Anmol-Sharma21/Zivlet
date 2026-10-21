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

    @Test func theSettingsThemeIsUsedUnlessALaunchArgumentNamesOne() throws {
        let defaults = try #require(UserDefaults(suiteName: "zivlet-tests-\(UUID().uuidString)"))
        #expect(WheelTheme.preferred(settings: .solid, defaults: defaults) == .solid)
        defaults.set("glass", forKey: WheelAppearance.themeKey)
        #expect(WheelTheme.preferred(settings: .solid, defaults: defaults) == .glass)
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
