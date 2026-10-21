import CoreGraphics
import Darwin
import Foundation
import ImageIO
import ZivletCore
import ZivletEngineKit

/// Raster conversions and images → PDF in-process with ImageIO and Quartz (P1-24, P1-26 subset).
public struct ImageEngine: Engine {
    public let id = EngineID.image

    let writableTypes: Set<String>
    let options: ImageOptions
    let registry: FormatRegistry

    public init(
        writableTypes: Set<String> = ImageEngine.systemWritableTypes(), options: ImageOptions = ImageOptions(),
        registry: FormatRegistry = .standard
    ) {
        self.writableTypes = writableTypes
        self.options = options
        self.registry = registry
    }

    /// `CGImageDestinationCopyTypeIdentifiers()`, the ImageIO capability gate (13 §2.1: never hard-coded).
    public static func systemWritableTypes() -> Set<String> {
        Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
    }

    public func handles(_ pair: ConversionPair) -> Bool {
        [.raster, .svg].contains(registry.format(pair.source).category)
            && [.raster, .pdf].contains(registry.format(pair.target).category)
    }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        guard
            let missing = ImageRoutes.missing(
                source: pair.source, target: pair.target, writableTypes: writableTypes, registry: registry)
        else { return .available }
        return .unavailable(missing)
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        if let missing = ImageRoutes.missing(
            source: request.input.format, target: request.target, writableTypes: writableTypes, registry: registry)
        {
            throw .routeUnavailable(request.input.format, request.target, missing)
        }
        let url = request.input.url
        let isSVG = request.input.format == .svg
        let probe = try await BlockingWork.run { _ throws(JobError) in
            try isSVG ? SVGRenderer.probe(url) : ImageReader.probe(url)
        }
        return try ImagePlanner.plan(
            request, probe: probe, staged: workspace.stagedFile, writableTypes: writableTypes, options: options,
            registry: registry)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        for (index, stage) in plan.stages.enumerated() {
            guard let spec = stage.image else { throw .internalInvariant("image engine got a non-image stage") }
            let staged = plan.stagedFile
            try await BlockingWork.run { flag throws(JobError) in try ImagePipeline.run(spec, to: staged, cancel: flag)
            }
            context.progress.report(plan.overallFraction(stage: index, fraction: 1))
        }
        var info = stat()
        let size = stat(plan.stagedFile.path, &info) == 0 ? Int64(info.st_size) : 0
        return StagedOutput(format: plan.outputFormat, url: plan.stagedFile, byteCount: size)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        guard let spec = plan.stages.last?.image else { throw .internalInvariant("image plan without an image stage") }
        guard output.byteCount > 0 else { throw .verificationFailed("The output file is empty.") }
        let url = output.url
        try await BlockingWork.run { _ throws(JobError) in try ImageVerifier.check(url, spec: spec) }
    }
}

/// Header reads (no pixel decode) for probing and verification.
enum ImageReader {
    static func probe(_ url: URL) throws(JobError) -> ImageProbe {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options), let type = CGImageSourceGetType(source),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw .unsupportedInput(.unreadable) }
        return ImageProbe(
            typeIdentifier: type as String, frameCount: CGImageSourceGetCount(source),
            pixelSize: PixelSize(width: width, height: height),
            orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1,
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
            dpiWidth: PDFPageGeometry.dpi(properties[kCGImagePropertyDPIWidth]),
            dpiHeight: PDFPageGeometry.dpi(properties[kCGImagePropertyDPIHeight]), hasGainMap: hasGainMap(source))
    }

    /// No encoder Zivlet writes with keeps a gain map, so such a source is decoded to standard range and says so.
    static func hasGainMap(_ source: CGImageSource) -> Bool {
        [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap].contains { type in
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type) != nil
        }
    }
}

/// Re-opens the staged file (03b §6.1 "verify by re-opening the output"): type, displayed size, alpha, frame or
/// page count.
enum ImageVerifier {
    static let unexpectedAlpha = "The output has transparency the source did not have."

    static func check(_ url: URL, spec: ImagePipelineSpec) throws(JobError) {
        switch spec.output {
        case .pdf: try checkPDF(url, spec: spec)
        case .raster: try checkRaster(url, spec: spec)
        }
    }

    private static func checkRaster(_ url: URL, spec: ImagePipelineSpec) throws(JobError) {
        let probe: ImageProbe
        do {
            probe = try ImageReader.probe(url)
        } catch {
            throw .verificationFailed("The output could not be read back.")
        }
        guard probe.typeIdentifier == spec.destinationType else {
            throw .verificationFailed("The output is \(probe.typeIdentifier), expected \(spec.destinationType).")
        }
        guard probe.displaySize == spec.expectedSize else {
            throw .verificationFailed("The output is \(probe.displaySize), expected \(spec.expectedSize).")
        }
        if spec.flattenAlpha, probe.hasAlpha { throw .verificationFailed("The output still has transparency.") }
        if let webp = spec.webp, !webp.exactAlpha, probe.hasAlpha { throw .verificationFailed(unexpectedAlpha) }
        guard probe.frameCount == spec.frames.count else {
            let unit = probe.frameCount == 1 ? "frame" : "frames"
            throw .verificationFailed("The output has \(probe.frameCount) \(unit), expected \(spec.frames.count).")
        }
    }

    private static func checkPDF(_ url: URL, spec: ImagePipelineSpec) throws(JobError) {
        guard let document = CGPDFDocument(url as CFURL), let first = document.page(at: 1) else {
            throw .verificationFailed("The PDF could not be read back.")
        }
        guard document.numberOfPages == spec.frames.count else {
            throw .verificationFailed("The PDF has \(document.numberOfPages) pages, expected \(spec.frames.count).")
        }
        let box = first.getBoxRect(.mediaBox)
        let size = PixelSize(width: Int(box.width.rounded()), height: Int(box.height.rounded()))
        guard size == spec.expectedSize else {
            throw .verificationFailed("The first page is \(size) points, expected \(spec.expectedSize).")
        }
    }
}
