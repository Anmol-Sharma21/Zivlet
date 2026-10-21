import AppKit
import SwiftUI
import Testing
import ZivletCore
import ZivletWheelCore

@testable import ZivletWheel

/// FR-26: the highlighted petal's label against the pixels actually painted around it, not the flat base colour.
@Suite("Hot-petal label contrast (FR-26)")
@MainActor
struct LabelContrastTests {
    /// System accent colours (sRGB): blue, the fixture blue, purple, pink, orange, yellow, green, graphite, red, and
    /// three harder mid-luminance ones.
    nonisolated static let accents: [[Double]] = [
        [0, 0.478, 1], [0.2, 0.5, 0.9], [0.584, 0.239, 0.588], [0.97, 0.31, 0.62], [1, 0.58, 0], [1, 0.8, 0],
        [0.384, 0.729, 0.275], [0.549, 0.549, 0.549], [0.88, 0.22, 0.24], [0.5, 0.5, 0.5], [0.3, 0.3, 0.9],
        [0, 0.6, 0.6],
    ]

    static func palette(_ accent: [Double]) -> AccentPalette {
        AccentPalette(base: RGB(r: accent[0], g: accent[1], b: accent[2]))
    }

    /// A label can sit over most of the petal (side slots, two-line action labels), so every painted stop counts.
    @Test(arguments: accents)
    func theLabelKeeps4_5To1OverEveryPartOfTheHighlight(accent: [Double]) {
        let palette = Self.palette(accent)
        let worst = palette.highlightSamples.map { $0.contrast(with: palette.labelOnAccent) }.min() ?? 0
        #expect(worst >= 4.5, "\(accent): \(worst)")
    }

    /// The same on the rendered solid wheel, over the box a two-line action label covers.
    @Test(arguments: accents)
    func theRenderedPetalAgrees(accent: [Double]) throws {
        let palette = Self.palette(accent)
        let worst = try Self.labelBackground(palette).map { $0.contrast(with: palette.labelOnAccent) }.min() ?? 0
        #expect(worst >= 4.5, "\(accent): \(worst)")
    }

    /// Only an accent that needs it loses some of the light → dark gradient (03a §2.7 stops otherwise).
    @Test func aLegibleAccentKeepsTheFullGradient() {
        let orange = AccentPalette(base: RGB(r: 1, g: 0.58, b: 0))
        #expect(orange.strength == 1 && orange.paintedLight == orange.light && orange.paintedDark == orange.dark)
        let blue = AccentPalette(base: RGB(r: 0, g: 0.478, b: 1))
        #expect(blue.strength < 1 && blue.strength > 0)
    }

    /// In Glass the highlight is opaque, so the desktop behind the panel cannot lower the label's contrast.
    @Test func theGlassHighlightIsOpaque() {
        #expect(WheelView.hotFillOpacity == 1)
    }

    /// The solid wheel with slot 0 highlighted and no label text, sampled over 46 × 38 pt around the label point.
    static func labelBackground(_ palette: AccentPalette) throws -> [RGB] {
        let slices = (0..<6).map {
            WheelSlice(id: "convert.\($0)", label: "", symbolName: nil, target: .convert(.png), badge: nil)
        }
        let store = WheelStore(feedback: FakeFeedback())
        store.present(
            WheelModel(mode: .convert, content: .slices(slices), idleHubLabel: "", highlighted: 0), emptyMessage: nil,
            appearance: WheelAppearance(theme: .solid, palette: palette, reduceMotion: true))
        store.expand()
        let renderer = ImageRenderer(content: WheelView(store: store).environment(\.colorScheme, .dark))
        let image = try #require(renderer.cgImage)
        let centre = WheelLayout.labelPoint(slot: 0, count: 6)
        var samples: [RGB] = []
        for dx in stride(from: -23.0, through: 23, by: 4) {
            for dy in stride(from: -19.0, through: 19, by: 4) {
                samples.append(try #require(pixel(image, at: CGPoint(x: centre.x + dx, y: centre.y + dy))))
            }
        }
        return samples
    }

    static func pixel(_ image: CGImage, at point: CGPoint) -> RGB? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(
            image,
            in: CGRect(
                x: -point.x, y: point.y - Double(image.height) + 1, width: Double(image.width),
                height: Double(image.height)))
        return RGB(r: Double(data[0]) / 255, g: Double(data[1]) / 255, b: Double(data[2]) / 255)
    }
}
