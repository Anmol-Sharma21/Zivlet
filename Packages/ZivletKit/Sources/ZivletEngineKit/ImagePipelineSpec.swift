import Foundation

/// Width and height in pixels.
public struct PixelSize: Sendable, Codable, Equatable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width)×\(height)" }
}

public enum ImageOutputKind: String, Sendable, Codable {
    case raster, pdf
}

/// What happens to colour: the source profile kept (default), or pixels converted to 8-bit sRGB with the source
/// profile dropped (the Web setting, 03b §6.3).
public enum ImageColour: String, Sendable, Codable {
    case keep, convertToSRGB
}

/// One ImageIO / Quartz pass (03b §6.1–6.2): which frames of `source` to write, as which type, with which settings.
/// `expectedSize` is the displayed size (EXIF orientation applied) that verification compares against. `webp` set
/// means libwebp writes the frames instead of ImageIO (D-M4-8); `svg` set means the source is an SVG rendered by
/// zivlet-svg instead of decoded by ImageIO (D-M4-6).
/// Invariant: at least one frame, frame indices non-negative, quality (when set) in 0...1.
public struct ImagePipelineSpec: Sendable, Codable, Equatable {
    public let source: URL
    public let destinationType: String
    public let output: ImageOutputKind
    public let frames: [Int]
    public let flattenAlpha: Bool
    public let quality: Double?
    public let tiffLZW: Bool
    public let expectedSize: PixelSize
    public let webp: WebPOptions?
    public let svg: SVGRasterOptions?
    public let colour: ImageColour

    public init(
        source: URL, destinationType: String, output: ImageOutputKind, frames: [Int], flattenAlpha: Bool,
        quality: Double?, tiffLZW: Bool, expectedSize: PixelSize, webp: WebPOptions? = nil,
        svg: SVGRasterOptions? = nil, colour: ImageColour = .keep
    ) throws(PlanError) {
        guard !frames.isEmpty, frames.allSatisfy({ $0 >= 0 }) else { throw .noFrames }
        if let quality, !(0...1).contains(quality) { throw .badQuality }
        self.source = source
        self.destinationType = destinationType
        self.output = output
        self.frames = frames
        self.flattenAlpha = flattenAlpha
        self.quality = quality
        self.tiffLZW = tiffLZW
        self.expectedSize = expectedSize
        self.webp = webp
        self.svg = svg
        self.colour = colour
    }
}

extension ImagePipelineSpec {
    private enum CodingKeys: String, CodingKey {
        case source, destinationType, output, frames, flattenAlpha, quality, tiffLZW, expectedSize, webp, svg, colour
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                source: c.decode(URL.self, forKey: .source),
                destinationType: c.decode(String.self, forKey: .destinationType),
                output: c.decode(ImageOutputKind.self, forKey: .output), frames: c.decode([Int].self, forKey: .frames),
                flattenAlpha: c.decode(Bool.self, forKey: .flattenAlpha),
                quality: c.decodeIfPresent(Double.self, forKey: .quality),
                tiffLZW: c.decode(Bool.self, forKey: .tiffLZW),
                expectedSize: c.decode(PixelSize.self, forKey: .expectedSize),
                webp: c.decodeIfPresent(WebPOptions.self, forKey: .webp),
                svg: c.decodeIfPresent(SVGRasterOptions.self, forKey: .svg),
                colour: c.decodeIfPresent(ImageColour.self, forKey: .colour) ?? .keep)
        } catch let error as PlanError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid image spec", underlyingError: error))
        }
    }
}
