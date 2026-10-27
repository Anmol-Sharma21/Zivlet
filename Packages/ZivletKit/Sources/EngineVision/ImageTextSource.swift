import CoreGraphics
import Foundation
import ImageIO

/// The text of one image file (P2-104). The header is checked before any decode: more than 200 MP (the image
/// engine's per-frame limit, `ImagePlanner.maxPixels`) is refused. The image is decoded with its EXIF orientation
/// applied, its longest side capped at 8192 px and its area at 25 MP, so one large photo cannot hold hundreds of MB
/// in the worker (a rendered PDF page is capped at 16 MP; a photo keeps a little more, for small text).
public enum ImageTextSource {
    public static let maximumHeaderPixels = 200_000_000
    public static let maximumSide = 8192
    public static let maximumDecodePixels = 25_000_000

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
            kCGImageSourceThumbnailMaxPixelSize: decodeSide(width: width, height: height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else {
            throw .unreadable
        }
        return image
    }

    /// The longest side to decode to: the image's own, scaled down so the area stays within `maximumDecodePixels`
    /// (with the short side rounded up, as ImageIO may) and the side within `maximumSide`.
    public static func decodeSide(width: Int, height: Int) -> Int {
        let longest = Double(max(width, height))
        let ratio = Double(min(width, height)) / longest
        let cap = Double(maximumDecodePixels)
        var side = min(maximumSide, max(1, Int((longest * min(1, (cap / (longest * longest * ratio)).squareRoot())))))
        while side > 1, Double(side) * (Double(side) * ratio).rounded(.up) > cap { side -= 1 }
        return side
    }

    /// `%PDF-` at the start of the file.
    public static func isPDF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 5)) ?? Data()
        return head == Data("%PDF-".utf8)
    }
}
