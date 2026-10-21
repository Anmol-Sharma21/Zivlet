import Foundation
import ZivletCore
import ZivletEngineKit

/// Header facts about a source image (read without decoding pixels, 03b §6.1).
public struct ImageProbe: Sendable, Equatable {
    public let typeIdentifier: String
    public let frameCount: Int
    public let pixelSize: PixelSize
    /// EXIF orientation 1…8 (1 when absent or invalid).
    public let orientation: Int
    public let hasAlpha: Bool
    /// Stored pixels per inch on each axis (72 when the file names none).
    public let dpiWidth: Double
    public let dpiHeight: Double

    public init(
        typeIdentifier: String, frameCount: Int, pixelSize: PixelSize, orientation: Int, hasAlpha: Bool,
        dpiWidth: Double = PDFPageGeometry.defaultDPI, dpiHeight: Double = PDFPageGeometry.defaultDPI
    ) {
        self.typeIdentifier = typeIdentifier
        self.frameCount = frameCount
        self.pixelSize = pixelSize
        self.orientation = (1...8).contains(orientation) ? orientation : 1
        self.hasAlpha = hasAlpha
        self.dpiWidth = dpiWidth
        self.dpiHeight = dpiHeight
    }

    /// Orientations 5–8 rotate by 90°, so the displayed size swaps width and height.
    public var displaySize: PixelSize {
        orientation >= 5 ? PixelSize(width: pixelSize.height, height: pixelSize.width) : pixelSize
    }

    /// The PDF page for this image, in points, rounded as verification compares it.
    var pageSize: PixelSize {
        let size = PDFPageGeometry.pageSize(
            orientation: orientation, stored: pixelSize, dpiX: dpiWidth, dpiY: dpiHeight)
        return PixelSize(width: Int(size.width.rounded()), height: Int(size.height.rounded()))
    }
}

public struct ImageOptions: Sendable, Equatable {
    public let tier: QualityTier

    public init(tier: QualityTier = .standard) { self.tier = tier }
}

/// Pure plan builder for raster → raster and raster → PDF (P1-08, P1-10; 03b §6.2).
public enum ImagePlanner {
    /// 10 §8.9: decode cap.
    public static let maxPixels = 200_000_000
    /// All frames of one job (TIFF pages into one PDF): five full-size frames.
    public static let maxPixelsPerJob = 1_000_000_000
    public static let maxPDFPages = 1_000
    static let lossy: Set<FormatID> = [.jpg, .heic, .avif]
    static let opaqueTargets: Set<FormatID> = [.jpg, .bmp]

    /// Compact / Balanced / High for JPEG, HEIC and AVIF (03b §6.2).
    public static func quality(_ tier: QualityTier) -> Double {
        switch tier {
        case .small: 0.65
        case .standard: 0.85
        case .best: 0.96
        }
    }

    public static func plan(
        _ request: JobRequest, probe: ImageProbe, staged: URL, writableTypes: Set<String>,
        options: ImageOptions = ImageOptions(), registry: FormatRegistry = .standard
    ) throws(JobError) -> ExecutionPlan {
        let source = request.input.format
        let target = request.target
        if let missing = ImageRoutes.missing(
            source: source, target: target, writableTypes: writableTypes, registry: registry)
        {
            throw .routeUnavailable(source, target, missing)
        }
        let pixels = probe.pixelSize.width.multipliedReportingOverflow(by: probe.pixelSize.height)
        guard probe.pixelSize.width > 0, probe.pixelSize.height > 0 else { throw .unsupportedInput(.unreadable) }
        guard !pixels.overflow, pixels.partialValue <= maxPixels else { throw .unsupportedInput(.tooLarge) }
        let webp = target == .webp ? WebPPlanner.options(tier: options.tier, probe: probe) : nil
        if webp != nil, !WebPPlanner.fits(probe.displaySize) { throw .unsupportedInput(.tooLarge) }
        let frames =
            webp.map { WebPPlanner.frames(probe: probe, animated: $0.animated) }
            ?? frames(source: source, target: target, probe: probe)
        let flatten = opaqueTargets.contains(target) && probe.hasAlpha
        let notes =
            (flatten ? [PlanNote.alphaFlattened] : []) + (frames.count < probe.frameCount ? [.firstFrameOnly] : [])
        do {
            let spec = try ImagePipelineSpec(
                source: request.input.url, destinationType: registry.format(target).contentTypes[0],
                output: target == .pdf ? .pdf : .raster, frames: frames, flattenAlpha: flatten,
                quality: lossy.contains(target) ? quality(options.tier) : nil, tiffLZW: target == .tiff,
                expectedSize: target == .pdf ? probe.pageSize : probe.displaySize, webp: webp)
            return try ExecutionPlan(
                engine: .image, stages: [.image(spec)], stageWeights: [1], lanes: [.cpu], outputFormat: target,
                stagedFile: staged, notes: notes)
        } catch {
            throw .internalInvariant("image plan rejected: \(error)")
        }
    }

    /// Every page of a TIFF into a PDF; otherwise the first frame (03b §6.2: animation flattened to the first frame).
    static func frames(source: FormatID, target: FormatID, probe: ImageProbe) -> [Int] {
        guard target == .pdf, source == .tiff else { return [0] }
        return Array(0..<min(max(probe.frameCount, 1), maxPDFPages))
    }
}

/// Route gate for images (03a §3.5): SVG input needs the renderer M3 does not ship yet (index D-M3-7); WebP is
/// written by the linked libwebp (D-M4-8) and PDF by Quartz; every other raster target needs ImageIO to list its type
/// as writable.
public enum ImageRoutes {
    public static func missing(
        source: FormatID, target: FormatID, writableTypes: Set<String>, registry: FormatRegistry = .standard
    ) -> [String]? {
        if source == .svg { return ["svg renderer"] }
        if target == .pdf || target == .webp { return nil }
        let type = registry.format(target).contentTypes[0]
        return writableTypes.contains(type) ? nil : ["ImageIO \(type) encoder"]
    }
}
