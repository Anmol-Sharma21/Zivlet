import Foundation
import ZivletCore
import ZivletEngineKit

/// libwebp settings and frames for the raster → webp pairs (P1-09, 03b §6.2 row `webp`). Lossy at the tier quality,
/// method 4, sharp YUV, exact RGB under transparency when the source has alpha, metadata kept. Lossless is never
/// picked automatically in Phase 1, so a lossless file larger than the source cannot appear silently. An APNG or
/// HEIC sequence stays animated; every other multi-frame source keeps its first frame. Pure.
public enum WebPPlanner {
    static let method = 4
    static let animatedTypes: Set<String> = ["public.png", "public.heics"]
    /// Most frames one animated WebP carries; the job pixel budget can lower it further.
    static let maxFrames = 1_000
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
                animated: isAnimated(probe), keepICC: true, keepEXIF: true, keepXMP: true)
        } catch {
            preconditionFailure("the WebP ladder and method are inside libwebp's ranges")
        }
    }

    /// False when a side is past `maxEdge`; such sources are refused before any decode.
    static func fits(_ size: PixelSize) -> Bool { max(size.width, size.height) <= maxEdge }

    static func isAnimated(_ probe: ImageProbe) -> Bool {
        probe.frameCount > 1 && animatedTypes.contains(probe.typeIdentifier)
    }

    /// Every frame of an animation, at most `maxFrames` and as many as `ImagePlanner.maxPixelsPerJob` admits;
    /// otherwise frame 0.
    static func frames(probe: ImageProbe, animated: Bool) -> [Int] {
        guard animated else { return [0] }
        let pixels = max(probe.pixelSize.width * probe.pixelSize.height, 1)
        let budget = max(ImagePlanner.maxPixelsPerJob / pixels, 1)
        return Array(0..<min(probe.frameCount, maxFrames, budget))
    }
}
