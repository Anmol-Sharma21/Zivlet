import CoreGraphics
import Foundation
import ImageIO
import ZivletCore
import ZivletEngineKit

/// Images → PDF with Quartz (03b §6.2, P1-10): one page per frame, sized to the displayed image at its DPI. A JPEG
/// in RGB or grey is embedded as its own bytes (DCT, no re-encode, no decode in Zivlet); other frames are decoded
/// at full size without orientation. Either way the orientation is applied once, by the page transform.
enum ImagePDFWriter {
    static let jpegType = "public.jpeg"
    static let passthroughModels: Set<String> = ["RGB", "Gray"]

    static func write(
        _ source: CGImageSource, _ spec: ImagePipelineSpec, to staged: URL, cancel: CancellationFlag,
        budget start: PixelBudget
    ) throws(JobError) {
        try StagedFile.check(staged)  // Quartz opens the path and follows a symlink there
        guard let context = CGContext(staged as CFURL, mediaBox: nil, nil) else {
            throw ImageWriteFailure.error(at: staged)
        }
        var budget = start
        for index in spec.frames {
            do throws(JobError) {
                if cancel.isCancelled { throw .cancelled }
                budget = try budget.admitting(source, index)
                try drawPage(source, index, spec: spec, into: context)
            } catch {
                context.closePDF()
                throw error
            }
        }
        context.closePDF()
        guard ImageWriteFailure.isWritten(staged) else { throw ImageWriteFailure.error(at: staged) }
    }

    /// One page of `page` points holding `image` scaled to fill it (an SVG's picture, D-M4-6).
    static func writePicture(_ image: CGImage, page: PixelSize, to staged: URL) throws(JobError) {
        try StagedFile.check(staged)
        guard let context = CGContext(staged as CFURL, mediaBox: nil, nil) else {
            throw ImageWriteFailure.error(at: staged)
        }
        var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        context.beginPDFPage(
            [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.interpolationQuality = .high
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        guard ImageWriteFailure.isWritten(staged) else { throw ImageWriteFailure.error(at: staged) }
    }

    private static func drawPage(
        _ source: CGImageSource, _ index: Int, spec: ImagePipelineSpec, into context: CGContext
    )
        throws(JobError)
    {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let image: CGImage
        if let jpeg = try passthrough(source, index, properties, spec: spec) {
            image = jpeg
        } else {
            image = try decoded(source, index)
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        var box = CGRect(
            origin: .zero,
            size: PDFPageGeometry.pageSize(
                orientation: orientation, stored: PixelSize(width: image.width, height: image.height),
                dpiX: PDFPageGeometry.dpi(properties[kCGImagePropertyDPIWidth]),
                dpiY: PDFPageGeometry.dpi(properties[kCGImagePropertyDPIHeight])))
        let placement = PDFPageGeometry.placement(orientation: orientation, page: box.size)
        context.beginPDFPage(
            [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        context.concatenate(placement.transform)
        context.draw(image, in: placement.rect)
        context.endPDFPage()
    }

    /// The JPEG's own bytes as an image Quartz embeds unchanged; nil for other types, CMYK or anything it refuses.
    private static func passthrough(
        _ source: CGImageSource, _ index: Int, _ properties: [CFString: Any], spec: ImagePipelineSpec
    ) throws(JobError) -> CGImage? {
        guard index == 0, CGImageSourceGetType(source) as String? == jpegType,
            let model = properties[kCGImagePropertyColorModel] as? String, passthroughModels.contains(model)
        else { return nil }
        guard let data = try? Data(contentsOf: spec.source, options: .mappedIfSafe),
            let provider = CGDataProvider(data: data as CFData)
        else { throw .unsupportedInput(.unreadable) }
        return CGImage(
            jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The stored pixels, decoded once; orientation is left to the page transform.
    private static func decoded(_ source: CGImageSource, _ index: Int) throws(JobError) -> CGImage {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, index, options) else {
            throw .unsupportedInput(.unreadable)
        }
        return image
    }
}
