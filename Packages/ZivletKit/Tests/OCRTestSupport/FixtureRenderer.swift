import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension OCRFixtures {
    /// The margin around the text, in pixels.
    static let margin = 40
    /// The widest and tallest text frame CoreText may suggest.
    static let frameLimit = CGSize(width: 1400, height: 2000)
    /// The dark fixture's background, `#1F2129`.
    static let darkBackground = CGColor(srgbRed: 0x1F / 255, green: 0x21 / 255, blue: 0x29 / 255, alpha: 1)

    /// The fixture's file bytes: a PNG, or for `.degraded` the fixed chain and a JPEG.
    public static func encoded(_ entry: Entry, degradation: Degradation = .fixture) throws -> Data {
        let image = try draw(entry)
        guard entry.style == .degraded else { return try FixtureImage.png(image) }
        return try FixtureImage.jpeg(degradation.apply(to: image), quality: degradation.jpegQuality)
    }

    /// The fixture as Vision would read it from its file.
    public static func image(for entry: Entry, degradation: Degradation = .fixture) throws -> CGImage {
        try FixtureImage.decode(encoded(entry, degradation: degradation))
    }

    /// The text drawn with CoreText into an opaque sRGB bitmap, with the margin; fails when the font is missing or
    /// any run of the text was drawn with another font. The geometry is the one the plan's measurements used (the
    /// suggested frame plus one point, the bitmap rounded up). It was pinned after Vision's result on fixtures 02 and
    /// 06 was seen to change when the frame grew by one pixel, so the 12/12 holds for this geometry; it is not tuned
    /// further.
    public static func draw(_ entry: Entry) throws(OCRFixtureError) -> CGImage {
        let font = CTFontCreateWithName(entry.font as CFString, CGFloat(entry.size), nil)
        guard CTFontCopyPostScriptName(font) as String == entry.font else { throw .fontMissing(entry.font) }
        let dark = entry.style == .dark
        let ink = dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink]
        let text = CFAttributedStringCreate(nil, entry.text as CFString, attributes as CFDictionary)
        guard let text else { throw .renderFailed(entry.name) }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, frameLimit, nil)
        let area = CGRect(x: CGFloat(margin), y: CGFloat(margin), width: fit.width + 1, height: fit.height + 1)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: area, transform: nil), nil)
        try checkFonts(frame, entry: entry)
        let size = (
            width: Int((fit.width + CGFloat(2 * margin)).rounded(.up)),
            height: Int((fit.height + CGFloat(2 * margin)).rounded(.up))
        )
        guard let context = FixtureImage.context(width: size.width, height: size.height) else {
            throw .renderFailed(entry.name)
        }
        context.setFillColor(dark ? darkBackground : CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        CTFrameDraw(frame, context)
        guard let image = context.makeImage() else { throw .renderFailed(entry.name) }
        return image
    }

    /// Every glyph run must use the fixture's own font.
    static func checkFonts(_ frame: CTFrame, entry: Entry) throws(OCRFixtureError) {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        for line in lines {
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let value = attributes[kCTFontAttributeName], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID()
                else { throw .fontFallback(fixture: entry.name, used: "none") }
                let used = CTFontCopyPostScriptName(unsafeDowncast(value as AnyObject, to: CTFont.self)) as String
                guard used == entry.font || used == entry.fallback else {
                    throw .fontFallback(fixture: entry.name, used: used)
                }
            }
        }
    }
}

/// Bitmap contexts and the encoders the fixtures use.
enum FixtureImage {
    static func context(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    static func png(_ image: CGImage) throws(OCRFixtureError) -> Data {
        try encode(image, type: .png, properties: [:])
    }

    static func jpeg(_ image: CGImage, quality: Double) throws(OCRFixtureError) -> Data {
        try encode(image, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func decode(_ data: Data) throws(OCRFixtureError) -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw .renderFailed("decode") }
        return image
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]) throws(OCRFixtureError)
        -> Data
    {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw .renderFailed("encode")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .renderFailed("encode") }
        return data as Data
    }
}
