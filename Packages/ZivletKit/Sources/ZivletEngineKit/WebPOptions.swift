import Foundation

/// libwebp settings for one WebP output (03b §6.2 row `webp`, P1-09): lossy `quality` 0…100 and `method` 0…6 as
/// libwebp names them, sharp RGB → YUV, exact RGB under transparent pixels, frames written as an animation, and
/// which source metadata chunks are carried. Invariant: quality in 0...100, method in 0...6.
public struct WebPOptions: Sendable, Codable, Equatable {
    public static let qualityRange = 0.0...100.0
    public static let methodRange = 0...6

    public let quality: Double
    public let method: Int
    public let sharpYUV: Bool
    public let exactAlpha: Bool
    public let lossless: Bool
    public let animated: Bool
    public let keepICC: Bool
    public let keepEXIF: Bool
    public let keepXMP: Bool

    public init(
        quality: Double, method: Int, sharpYUV: Bool, exactAlpha: Bool, lossless: Bool, animated: Bool,
        keepICC: Bool, keepEXIF: Bool, keepXMP: Bool
    ) throws(PlanError) {
        guard Self.qualityRange.contains(quality) else { throw .badQuality }
        guard Self.methodRange.contains(method) else { throw .badMethod }
        self.quality = quality
        self.method = method
        self.sharpYUV = sharpYUV
        self.exactAlpha = exactAlpha
        self.lossless = lossless
        self.animated = animated
        self.keepICC = keepICC
        self.keepEXIF = keepEXIF
        self.keepXMP = keepXMP
    }
}

extension WebPOptions {
    private enum CodingKeys: String, CodingKey {
        case quality, method, sharpYUV, exactAlpha, lossless, animated, keepICC, keepEXIF, keepXMP
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                quality: c.decode(Double.self, forKey: .quality), method: c.decode(Int.self, forKey: .method),
                sharpYUV: c.decode(Bool.self, forKey: .sharpYUV), exactAlpha: c.decode(Bool.self, forKey: .exactAlpha),
                lossless: c.decode(Bool.self, forKey: .lossless), animated: c.decode(Bool.self, forKey: .animated),
                keepICC: c.decode(Bool.self, forKey: .keepICC), keepEXIF: c.decode(Bool.self, forKey: .keepEXIF),
                keepXMP: c.decode(Bool.self, forKey: .keepXMP))
        } catch let error as PlanError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid WebP options", underlyingError: error))
        }
    }
}
