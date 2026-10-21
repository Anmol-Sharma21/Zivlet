import CoreGraphics
import Foundation
import ImageIO
import ZivletCore
import ZivletEngineKit

/// Executes an `ImagePipelineSpec` with ImageIO and Quartz (03b §6.1); PDF pages are `ImagePDFWriter`'s. Untouched frames go through
/// `CGImageDestinationAddImageFromSource`, which keeps ICC profile, bit depth (where the target allows it), EXIF, XMP
/// and the orientation tag, and converts CMYK for targets without it. Frames that need pixels changed (alpha
/// flattened, or an orientation the target's readers would ignore, see `OrientationPolicy`) are decoded once with the
/// orientation applied (so it is applied exactly once) and written with orientation 1. Callers run it
/// through `BlockingWork` (index D-M3-10); `cancel` is polled between frames.
enum ImagePipeline {
    static func run(
        _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag, limits: PixelLimits = .standard
    ) throws(JobError) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(spec.source as CFURL, options) else {
            throw .unsupportedInput(.unreadable)
        }
        let budget = PixelBudget(limits)
        switch spec.output {
        case .raster where spec.webp != nil: try writeWebP(source, spec, to: staged, cancel: cancel, budget: budget)
        case .raster: try writeRaster(source, spec, to: staged, cancel: cancel, budget: budget)
        case .pdf: try ImagePDFWriter.write(source, spec, to: staged, cancel: cancel, budget: budget)
        }
    }

    private static func writeRaster(
        _ source: CGImageSource, _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag,
        budget start: PixelBudget
    ) throws(JobError) {
        guard
            let destination = CGImageDestinationCreateWithURL(
                staged as CFURL, spec.destinationType as CFString, spec.frames.count, nil)
        else { throw ImageWriteFailure.error(at: staged) }
        var budget = start
        for index in spec.frames {
            if cancel.isCancelled { throw .cancelled }
            budget = try budget.admitting(source, index)
            try addFrame(index, of: source, to: destination, spec)
        }
        guard CGImageDestinationFinalize(destination) else { throw ImageWriteFailure.error(at: staged) }
    }

    /// libwebp instead of ImageIO (D-M4-8): every planned frame decoded upright, within the pixel budget.
    private static func writeWebP(
        _ source: CGImageSource, _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag,
        budget start: PixelBudget
    ) throws(JobError) {
        guard let options = spec.webp else { throw .internalInvariant("WebP output without WebP options") }
        let job = WebPWriter.Job(
            count: spec.frames.count, canvas: spec.expectedSize, timing: WebPTiming.read(source, frames: spec.frames),
            metadata: WebPMetadata.read(source, index: spec.frames[0], output: spec.expectedSize, options: options),
            options: options)
        var budget = start
        try WebPWriter.write(job, to: staged, cancel: cancel) { (position: Int) throws(JobError) -> CGImage in
            let index = spec.frames[position]
            budget = try budget.admitting(source, index)
            return try oriented(source, index)
        }
    }

    /// Copies the frame as stored (tag kept) unless it needs flattening or its orientation baked in
    /// (`OrientationPolicy`); then it is decoded upright once and written with orientation 1.
    private static func addFrame(
        _ index: Int, of source: CGImageSource, to destination: CGImageDestination, _ spec: ImagePipelineSpec
    ) throws(JobError) {
        let encode = encodeProperties(spec)
        let metadata = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let orientation = metadata[kCGImagePropertyOrientation] as? Int ?? 1
        guard spec.flattenAlpha || OrientationPolicy.bakes(orientation, into: spec.destinationType) else {
            CGImageDestinationAddImageFromSource(destination, source, index, encode as CFDictionary)
            return
        }
        let upright = try oriented(source, index)
        let image = spec.flattenAlpha ? try flattened(upright) : upright
        let properties = OrientationPolicy.upright(metadata).merging(encode) { _, new in new }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    }

    /// LZW in strips (03b §6.2). A source that carries tile sizes in its TIFF dictionary (HEIC, some cameras) makes
    /// `AddImageFromSource` write uncompressed tiles whatever `Compression` says, so the tile sizes are reset to 0.
    static func encodeProperties(_ spec: ImagePipelineSpec) -> [CFString: Any] {
        var properties: [CFString: Any] = [:]
        if let quality = spec.quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        if spec.tiffLZW {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: TIFFCompression.lzw, kCGImagePropertyTIFFTileWidth: 0,
                kCGImagePropertyTIFFTileLength: 0,
            ]
        }
        return properties
    }

    /// Full-size decode with the EXIF orientation applied; keeps the source's bit depth and colour space.
    static func oriented(_ source: CGImageSource, _ index: Int) throws(JobError) -> CGImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1), kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw .unsupportedInput(.unreadable)
        }
        return image
    }

    /// Draws `image` over white into an opaque 8-bit context in its own RGB space (sRGB for other models).
    static func flattened(_ image: CGImage) throws(JobError) -> CGImage {
        let rgb = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let space = rgb ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw .internalInvariant("cannot create a flattening context") }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        guard let flat = context.makeImage() else { throw .internalInvariant("cannot flatten the image") }
        return flat
    }
}

/// TIFF tag values (03b §6.2).
enum TIFFCompression {
    static let lzw = 5
}
