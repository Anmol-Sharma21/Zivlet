import CoreGraphics
import Foundation
import ImageIO

/// The text of one image file (P2-104). The header is checked before any decode: more than 200 MP (the image
/// engine's per-frame limit, `ImagePlanner.maxPixels`) is refused. The image is decoded with its EXIF orientation
/// applied and its longest side capped at 8192 px, like a rendered PDF page.
public enum ImageTextSource {
    public static let maximumHeaderPixels = 200_000_000
    public static let maximumSide = 8192

    public static func read(
        _ url: URL, recognizer: any TextRecognizing, languages: [LanguageTag],
        maximumPixels: Int = maximumHeaderPixels
    ) async throws(TextError) -> RecognizedPage {
        let image = try decode(url, maximumPixels: maximumPixels)
        return try await recognizer.recognize(image, languages: languages)
    }

    static func decode(_ url: URL, maximumPixels: Int) throws(TextError) -> CGImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { throw .unreadable }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= maximumPixels else { throw .tooLarge }
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maximumSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else {
            throw .unreadable
        }
        return image
    }

    /// `%PDF-` at the start of the file.
    public static func isPDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 5)) ?? Data()
        return head == Data("%PDF-".utf8)
    }
}
