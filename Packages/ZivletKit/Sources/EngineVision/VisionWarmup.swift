import CoreGraphics
import CoreText
import Foundation

/// The one-time warm-up (D-M6-16): Vision compiles its model per configuration and per input-size bucket on first
/// use, which took minutes on the build Mac (plan 18 §3.2), so three generated images are read once in the
/// production configuration: 64 px, 1024 px and a 2550 × 3300 page, each with one line per language. The worker
/// runs it at `.utility` priority.
public enum VisionWarmup {
    public static let sizes = [
        CGSize(width: 64, height: 64), CGSize(width: 1024, height: 1024), CGSize(width: 2550, height: 3300),
    ]

    public static func run(recognizer: any TextRecognizing, languages: [LanguageTag]) async throws(TextError) {
        for image in try images(languages: languages) {
            if Task.isCancelled { throw .cancelled }
            _ = try await recognizer.recognize(image, languages: languages)
        }
    }

    /// A short line of Zivlet's own words per language, in a font that ships with macOS.
    static func lines(for languages: [LanguageTag]) -> [(text: String, font: String)] {
        languages.map { language in
            language.script == LanguageTag.hindi.script
                ? ("पाठ की जाँच", "KohinoorDevanagari-Regular") : ("Text check", "HelveticaNeue")
        }
    }

    static func images(languages: [LanguageTag]) throws(TextError) -> [CGImage] {
        try sizes.map { size throws(TextError) in try draw(lines(for: languages), size: size) }
    }

    /// Black lines on white, the font scaled to the image (one tenth of its width, at most 48 px).
    static func draw(_ lines: [(text: String, font: String)], size: CGSize) throws(TextError) -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw .recognitionFailed("warm-up image") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let points = min(48, size.width / 10)
        for (index, line) in lines.enumerated() {
            let font = CTFontCreateWithName(line.font as CFString, points, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
            ]
            guard let text = CFAttributedStringCreate(nil, line.text as CFString, attributes as CFDictionary) else {
                continue
            }
            context.textPosition = CGPoint(x: points / 2, y: size.height - points * CGFloat(index + 1) * 1.5)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        guard let image = context.makeImage() else { throw .recognitionFailed("warm-up image") }
        return image
    }
}
