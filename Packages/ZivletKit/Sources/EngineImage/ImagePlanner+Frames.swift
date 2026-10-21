import Foundation
import ZivletCore
import ZivletEngineKit

/// Which frames a plan writes and as which type (03b §6.2, G-5): every page of a TIFF into a PDF; every frame of an
/// APNG or HEIC sequence into PNG (APNG), HEIC (a HEIC sequence, when ImageIO can write `public.heics`) or WebP;
/// otherwise the first frame. Pure.
extension ImagePlanner {
    static let animatedTypes: Set<String> = ["public.png", "public.heics"]
    static let heicSequenceType = "public.heics"
    /// Most frames one animation carries; the job pixel budget can lower it further.
    public static let maxAnimationFrames = 1_000

    static func isAnimated(_ probe: ImageProbe) -> Bool {
        probe.frameCount > 1 && animatedTypes.contains(probe.typeIdentifier)
    }

    /// Every frame of an animation, at most `maxAnimationFrames` and as many as `maxPixelsPerJob` admits.
    static func animationFrames(_ probe: ImageProbe) -> [Int] {
        let pixels = max(probe.pixelSize.width * probe.pixelSize.height, 1)
        let budget = max(maxPixelsPerJob / pixels, 1)
        return Array(0..<min(probe.frameCount, maxAnimationFrames, budget))
    }

    /// The destination type and frames for `target` (WebP's are `WebPPlanner`'s).
    static func layout(
        source: FormatID, target: FormatID, probe: ImageProbe, writableTypes: Set<String>, registry: FormatRegistry
    ) -> (type: String, frames: [Int]) {
        let type = registry.format(target).contentTypes[0]
        if target == .pdf, source == .tiff { return (type, Array(0..<min(max(probe.frameCount, 1), maxPDFPages))) }
        guard isAnimated(probe) else { return (type, [0]) }
        switch target {
        case .png: return (type, animationFrames(probe))
        case .heic where writableTypes.contains(heicSequenceType): return (heicSequenceType, animationFrames(probe))
        default: return (type, [0])
        }
    }
}
