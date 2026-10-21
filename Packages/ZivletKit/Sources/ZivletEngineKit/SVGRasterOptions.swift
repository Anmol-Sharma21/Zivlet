import Foundation

/// How an SVG source is rasterized (D-M4-6): CSS pixels times `scale`, the longest edge capped at `maxEdge` pixels
/// (lowered for costly filters, D-M4-18). `reservedPixels` is what zivlet-svg decodes besides the canvas (the largest
/// embedded raster image), for the decode budget. Invariant: scale finite and positive, maxEdge in 1...16383,
/// reservedPixels ≥ 0.
public struct SVGRasterOptions: Sendable, Codable, Equatable {
    public static let edgeRange = 1...16_383

    public let scale: Float
    public let maxEdge: Int
    public let reservedPixels: Int

    public init(scale: Float, maxEdge: Int, reservedPixels: Int = 0) throws(PlanError) {
        guard scale.isFinite, scale > 0, Self.edgeRange.contains(maxEdge), reservedPixels >= 0 else {
            throw .badScale
        }
        self.scale = scale
        self.maxEdge = maxEdge
        self.reservedPixels = reservedPixels
    }
}

extension SVGRasterOptions {
    private enum CodingKeys: String, CodingKey { case scale, maxEdge, reservedPixels }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                scale: c.decode(Float.self, forKey: .scale), maxEdge: c.decode(Int.self, forKey: .maxEdge),
                reservedPixels: c.decodeIfPresent(Int.self, forKey: .reservedPixels) ?? 0)
        } catch let error as PlanError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid SVG options", underlyingError: error))
        }
    }
}
