import Foundation
import ImageIO
import ZivletCore

/// Decode caps (10 §8.9), enforced by the pipeline on the image source it actually decodes: every frame is checked
/// before it is decoded (a small first page must not admit huge later ones, and a file swapped after the probe is
/// checked again), and all frames of one job share `perJob`.
public struct PixelLimits: Sendable, Equatable {
    public static let standard = PixelLimits(perFrame: ImagePlanner.maxPixels, perJob: ImagePlanner.maxPixelsPerJob)

    public let perFrame: Int
    public let perJob: Int

    public init(perFrame: Int, perJob: Int) {
        self.perFrame = perFrame
        self.perJob = perJob
    }
}

/// Pixels admitted so far for one job. Immutable: `admitting` returns the budget after one more frame.
struct PixelBudget: Sendable, Equatable {
    let limits: PixelLimits
    let spent: Int

    init(_ limits: PixelLimits, spent: Int = 0) {
        self.limits = limits
        self.spent = spent
    }

    /// Reads the frame's header size (no decode) and admits it, or throws `.tooLarge`.
    func admitting(_ source: CGImageSource, _ index: Int) throws(JobError) -> PixelBudget {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw .unsupportedInput(.unreadable) }
        let pixels = width.multipliedReportingOverflow(by: height)
        let total = spent.addingReportingOverflow(pixels.partialValue)
        guard !pixels.overflow, pixels.partialValue <= limits.perFrame, !total.overflow,
            total.partialValue <= limits.perJob
        else { throw .unsupportedInput(.tooLarge) }
        return PixelBudget(limits, spent: total.partialValue)
    }
}
