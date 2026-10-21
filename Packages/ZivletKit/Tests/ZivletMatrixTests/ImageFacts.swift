import CoreGraphics
import Foundation
import ImageIO

/// What ImageIO (or Core Graphics for PDF) says about an image file, for the property checks.
struct ImageFacts: Sendable, Equatable {
    let frames: Int
    /// Upright size: EXIF orientations 5–8 swap width and height.
    let width: Int
    let height: Int
    /// nil when unknown (an SVG before rasterization).
    let hasAlpha: Bool?
    /// The colour space or profile name, for example "Display P3"; nil when the file has none.
    let colourName: String?

    var isP3: Bool { colourName?.localizedCaseInsensitiveContains("P3") == true }

    /// The E1 drawing is 120 × 80 CSS pixels; Zivlet rasterizes SVG at 2× (D-M4-6).
    static let svgDrawing = ImageFacts(frames: 1, width: 240, height: 160, hasAlpha: nil, colourName: nil)

    static func read(_ url: URL) throws -> ImageFacts {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MatrixFailure("ImageIO cannot decode \(url.lastPathComponent)") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let swaps = (5...8).contains(orientation)
        let profile = properties[kCGImagePropertyProfileName] as? String
        return ImageFacts(
            frames: CGImageSourceGetCount(source), width: swaps ? image.height : image.width,
            height: swaps ? image.width : image.height, hasAlpha: hasAlpha(image),
            colourName: profile ?? image.colorSpace?.name.map { $0 as String })
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    }

    /// Page count of a PDF, or nil when Core Graphics cannot open it.
    static func pdfPages(_ url: URL) -> Int? {
        CGPDFDocument(url as CFURL).map(\.numberOfPages)
    }
}
