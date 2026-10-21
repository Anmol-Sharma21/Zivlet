import CoreGraphics
import Foundation
import ImageIO
import ZivletCore
import ZivletEngineKit

/// Executes a spec whose source is an SVG (D-M4-6): zivlet-svg renders it once, then the pixels go to ImageIO for
/// JPEG, PNG, HEIC, TIFF, AVIF and BMP, to `WebPWriter` for WebP, or onto one PDF page the size of the drawing.
enum SVGPipeline {
    static func run(
        _ spec: ImagePipelineSpec, _ options: SVGRasterOptions, to staged: URL, cancel: CancellationFlag
    ) throws(JobError) {
        let data = try SVGSource.read(spec.source)
        if cancel.isCancelled { throw .cancelled }
        let image = try SVGBitmap.render(data, options: options).image()
        if cancel.isCancelled { throw .cancelled }
        switch spec.output {
        case .pdf:
            try ImagePDFWriter.writePicture(image, page: spec.expectedSize, to: staged)
        case .raster:
            if let webp = spec.webp {
                let job = WebPWriter.Job(
                    count: 1, canvas: spec.expectedSize, timing: .still, metadata: .none, options: webp)
                try WebPWriter.write(job, to: staged, cancel: cancel) { (_: Int) throws(JobError) in image }
            } else {
                try writeRaster(image, spec, to: staged)
            }
        }
    }

    private static func writeRaster(_ image: CGImage, _ spec: ImagePipelineSpec, to staged: URL) throws(JobError) {
        let pixels = spec.flattenAlpha ? try ImagePipeline.flattened(image) : image
        guard
            let destination = CGImageDestinationCreateWithURL(
                staged as CFURL, spec.destinationType as CFString, 1, nil)
        else { throw ImageWriteFailure.error(at: staged) }
        CGImageDestinationAddImage(destination, pixels, ImagePipeline.encodeProperties(spec) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageWriteFailure.error(at: staged) }
    }
}
