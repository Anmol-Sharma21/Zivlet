import CoreGraphics
import Foundation

/// The fixed degradation of fixture 07 (plan 18d, D-M6-11), chosen before the recognizer existed and never tuned:
/// rotate about the centre on white, a 5-tap separable Gaussian blur, seeded uniform noise added equally to R, G and
/// B, then a JPEG. Every step is a pixel operation with a fixed seed, so two renders are byte-identical.
public struct Degradation: Sendable, Equatable {
    public let rotationDegrees: Double
    public let blurSigma: Double
    /// Half-width of the uniform noise as a fraction of full scale (0.04 is ±4 %).
    public let noise: Double
    public let seed: UInt64
    public let jpegQuality: Double

    public init(rotationDegrees: Double, blurSigma: Double, noise: Double, seed: UInt64, jpegQuality: Double) {
        self.rotationDegrees = rotationDegrees
        self.blurSigma = blurSigma
        self.noise = noise
        self.seed = seed
        self.jpegQuality = jpegQuality
    }

    /// Fixture 07's chain.
    public static let fixture = Degradation(
        rotationDegrees: 3, blurSigma: 0.9, noise: 0.04, seed: 0x5EED, jpegQuality: 0.35)

    /// The same chain with another noise level, for the unscored stress set.
    public func with(noise: Double) -> Degradation {
        Degradation(
            rotationDegrees: rotationDegrees, blurSigma: blurSigma, noise: noise, seed: seed, jpegQuality: jpegQuality)
    }

    func apply(to image: CGImage) throws(OCRFixtureError) -> CGImage {
        let pixels = try rotated(image).blurred(kernel: Self.kernel(sigma: blurSigma))
            .withNoise(amplitude: noise * 255, seed: seed)
        guard let result = pixels.image() else { throw .renderFailed("degrade") }
        return result
    }

    private func rotated(_ image: CGImage) throws(OCRFixtureError) -> Pixels {
        let (width, height) = (image.width, image.height)
        guard let context = FixtureImage.context(width: width, height: height) else { throw .renderFailed("rotate") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: rotationDegrees * .pi / 180)
        context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { throw .renderFailed("rotate") }
        let start = data.assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: start, count: width * height * 4))
        return Pixels(width: width, height: height, rgba: bytes)
    }

    /// Five normalised taps of a Gaussian.
    static func kernel(sigma: Double) -> [Double] {
        let raw = (-2...2).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = raw.reduce(0, +)
        return raw.map { $0 / sum }
    }
}

/// An opaque RGBA8 buffer the degradation steps work on.
struct Pixels {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    /// Horizontal then vertical pass over R, G and B, edges clamped; alpha stays opaque.
    func blurred(kernel: [Double]) -> Pixels {
        let across = pass(rgba, kernel: kernel, horizontal: true)
        return Pixels(width: width, height: height, rgba: pass(across, kernel: kernel, horizontal: false))
    }

    private func pass(_ source: [UInt8], kernel: [Double], horizontal: Bool) -> [UInt8] {
        var out = source
        let reach = kernel.count / 2
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    var sum = 0.0
                    for (tap, weight) in kernel.enumerated() {
                        let offset = tap - reach
                        let sx = horizontal ? min(max(x + offset, 0), width - 1) : x
                        let sy = horizontal ? y : min(max(y + offset, 0), height - 1)
                        sum += weight * Double(source[(sy * width + sx) * 4 + channel])
                    }
                    out[(y * width + x) * 4 + channel] = UInt8(min(max(sum.rounded(), 0), 255))
                }
            }
        }
        return out
    }

    /// Uniform noise in ±`amplitude` per pixel from a 64-bit LCG, the same value on R, G and B.
    func withNoise(amplitude: Double, seed: UInt64) -> Pixels {
        var out = rgba
        var state = seed
        for pixel in 0..<(width * height) {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double(state >> 11) / Double(UInt64(1) << 53)
            let delta = (unit * 2 - 1) * amplitude
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                out[index] = UInt8(min(max((Double(rgba[index]) + delta).rounded(), 0), 255))
            }
            out[pixel * 4 + 3] = 255
        }
        return Pixels(width: width, height: height, rgba: out)
    }

    func image() -> CGImage? {
        guard let context = FixtureImage.context(width: width, height: height), let data = context.data else {
            return nil
        }
        rgba.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { data.copyMemory(from: base, byteCount: bytes.count) }
        }
        return context.makeImage()
    }
}
