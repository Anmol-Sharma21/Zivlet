import CoreGraphics
import Foundation
import ImageIO
import ZivletCore
import ZivletEngineKit

/// Executes an `ImagePipelineSpec` with ImageIO and Quartz (03b §6.1); PDF pages are `ImagePDFWriter`'s, WebP is
/// `WebPWriter`'s and SVG sources are `SVGPipeline`'s. An APNG or HEIC sequence keeps its delays and loop count. Untouched frames go through
/// `CGImageDestinationAddImageFromSource`, which keeps ICC profile, bit depth (where the target allows it), EXIF, XMP
/// and the orientation tag, and converts CMYK for targets without it. Frames that need pixels changed (alpha
/// flattened, or an orientation the target's readers would ignore, see `OrientationPolicy`) are decoded once with the
/// orientation applied (so it is applied exactly once) and written with orientation 1. Callers run it
/// through `BlockingWork` (index D-M3-10); `cancel` is polled between frames.
enum ImagePipeline {
    /// `framesDone` hears each finished frame (raster and WebP outputs), for frame-based progress.
    static func run(
        _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag, limits: PixelLimits = .standard,
        framesDone: (Int) -> Void = { _ in }
    ) throws(JobError) {
        if let svg = spec.svg { return try SVGPipeline.run(spec, svg, to: staged, cancel: cancel) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(spec.source as CFURL, options) else {
            throw .unsupportedInput(.unreadable)
        }
        let budget = PixelBudget(limits)
        switch spec.output {
        case .raster where spec.webp != nil:
            try writeWebP(source, spec, to: staged, cancel: cancel, budget: budget, framesDone: framesDone)
        case .raster: try writeRaster(source, spec, to: staged, cancel: cancel, budget: budget, framesDone: framesDone)
        case .pdf: try ImagePDFWriter.write(source, spec, to: staged, cancel: cancel, budget: budget)
        }
    }

    private static func writeRaster(
        _ source: CGImageSource, _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag,
        budget start: PixelBudget, framesDone: (Int) -> Void
    ) throws(JobError) {
        guard
            let destination = CGImageDestinationCreateWithURL(
                staged as CFURL, spec.destinationType as CFString, spec.frames.count, nil)
        else { throw ImageWriteFailure.error(at: staged) }
        let timing = spec.frames.count > 1 ? AnimationTiming.read(source, frames: spec.frames) : nil
        if let timing {
            let file = AnimationTiming.fileProperties(spec.destinationType, loopCount: timing.loopCount)
            CGImageDestinationSetProperties(destination, file as CFDictionary)
        }
        var budget = start
        for (position, index) in spec.frames.enumerated() {
            if cancel.isCancelled { throw .cancelled }
            budget = try budget.admitting(source, index)
            let delay = timing?.frameProperties(spec.destinationType, position: position) ?? [:]
            try addFrame(index, of: source, to: destination, spec, extra: delay)
            framesDone(position + 1)
        }
        guard CGImageDestinationFinalize(destination) else { throw ImageWriteFailure.error(at: staged) }
    }

    /// libwebp instead of ImageIO (D-M4-8): every planned frame decoded upright, within the pixel budget.
    private static func writeWebP(
        _ source: CGImageSource, _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag,
        budget start: PixelBudget, framesDone: (Int) -> Void
    ) throws(JobError) {
        guard let options = spec.webp else { throw .internalInvariant("WebP output without WebP options") }
        let job = WebPWriter.Job(
            count: spec.frames.count, canvas: spec.expectedSize,
            timing: AnimationTiming.read(source, frames: spec.frames),
            metadata: WebPMetadata.read(source, index: spec.frames[0], output: spec.expectedSize, options: options),
            options: options, colour: spec.colour)
        var budget = start
        try WebPWriter.write(job, to: staged, cancel: cancel) { (position: Int) throws(JobError) -> CGImage in
            let index = spec.frames[position]
            budget = try budget.admitting(source, index)
            if position > 0 { framesDone(position) }
            return try oriented(source, index, standardRange: spec.decodeToSDR)
        }
        framesDone(spec.frames.count)
    }

    /// Copies the frame as stored (tag kept) unless it needs flattening or its orientation baked in
    /// (`OrientationPolicy`); then it is decoded upright once and written with orientation 1. `extra` (an animation
    /// frame's delay) is added to the encoder properties.
    private static func addFrame(
        _ index: Int, of source: CGImageSource, to destination: CGImageDestination, _ spec: ImagePipelineSpec,
        extra: [CFString: Any]
    ) throws(JobError) {
        let encode = encodeProperties(spec).merging(extra) { _, new in new }
        let metadata = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let orientation = metadata[kCGImagePropertyOrientation] as? Int ?? 1
        let converts = spec.colour == .convertToSRGB
        let decodes = converts || spec.decodeToSDR || spec.flattenAlpha
        guard decodes || OrientationPolicy.bakes(orientation, into: spec.destinationType) else {
            CGImageDestinationAddImageFromSource(destination, source, index, encode as CFDictionary)
            return
        }
        let upright = try oriented(source, index, standardRange: spec.decodeToSDR)
        let image =
            converts
            ? try redrawn(upright, into: RGBAFrame.srgb, flatten: spec.flattenAlpha)
            : spec.flattenAlpha ? try flattened(upright) : upright
        var properties = OrientationPolicy.upright(metadata).merging(encode) { _, new in new }
        if converts { properties[kCGImagePropertyProfileName] = nil }
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

    /// Full-size decode with the EXIF orientation applied; keeps the source's bit depth and colour space, or decodes
    /// standard range when `standardRange` (an HDR gain-map source).
    static func oriented(_ source: CGImageSource, _ index: Int, standardRange: Bool = false) throws(JobError)
        -> CGImage
    {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1), kCGImageSourceShouldCacheImmediately: true,
        ].merging(standardRange ? [kCGImageSourceDecodeRequest: kCGImageSourceDecodeToSDR] : [:]) { _, new in new }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw .unsupportedInput(.unreadable)
        }
        return image
    }

    /// Draws `image` over white into an opaque 8-bit context in its own RGB space (sRGB for other models).
    static func flattened(_ image: CGImage) throws(JobError) -> CGImage {
        let rgb = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        return try redrawn(image, into: rgb ?? RGBAFrame.srgb, flatten: true)
    }

    /// `image` drawn into an 8-bit context in `space` (Quartz converts the colours): over white and opaque when
    /// `flatten`, otherwise keeping transparency.
    static func redrawn(_ image: CGImage, into space: CGColorSpace, flatten: Bool) throws(JobError) -> CGImage {
        let opaque: Set<CGImageAlphaInfo> = [.none, .noneSkipLast, .noneSkipFirst]
        let info = flatten || opaque.contains(image.alphaInfo) ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: info.rawValue)
        else { throw .internalInvariant("cannot create a drawing context") }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if flatten {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
        }
        context.draw(image, in: bounds)
        guard let drawn = context.makeImage() else { throw .internalInvariant("cannot redraw the image") }
        return drawn
    }
}

/// TIFF tag values (03b §6.2).
enum TIFFCompression {
    static let lzw = 5
}
