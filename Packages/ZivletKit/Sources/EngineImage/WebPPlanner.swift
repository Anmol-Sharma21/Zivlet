import Foundation
import ZivletCore
import ZivletEngineKit

/// libwebp settings and frames for the raster → webp pairs (P1-09, 03b §6.2 row `webp`). Lossy at the tier quality,
/// method 4, sharp YUV, exact RGB under transparency when the source has alpha, metadata kept. Lossless is never
/// picked automatically in Phase 1, so a lossless file larger than the source cannot appear silently. An APNG or
/// HEIC sequence stays animated; every other multi-frame source keeps its first frame. Pure.
public enum WebPPlanner {
    static let method = 4
    /// libwebp's largest width or height (`WEBP_MAX_DIMENSION`).
    static let maxEdge = 16_383

    /// Compact / Balanced / High on libwebp's 0…100 scale (the same ladder as JPEG, HEIC and AVIF).
    public static func quality(_ tier: QualityTier) -> Double {
        switch tier {
        case .small: 65
        case .standard: 85
        case .best: 96
        }
    }

    public static func options(tier: QualityTier, probe: ImageProbe) -> WebPOptions {
        do {
            return try WebPOptions(
                quality: quality(tier), method: method, sharpYUV: true, exactAlpha: probe.hasAlpha, lossless: false,
                animated: ImagePlanner.isAnimated(probe), keepICC: true, keepEXIF: true, keepXMP: true)
        } catch {
            preconditionFailure("the WebP ladder and method are inside libwebp's ranges")
        }
    }

    /// False when a side is past `maxEdge`; such sources are refused before any decode.
    static func fits(_ size: PixelSize) -> Bool { max(size.width, size.height) <= maxEdge }

    /// Every frame of an animation (`ImagePlanner.animationFrames`), otherwise frame 0.
    static func frames(probe: ImageProbe, animated: Bool) -> [Int] {
        animated ? ImagePlanner.animationFrames(probe) : [0]
    }
}
