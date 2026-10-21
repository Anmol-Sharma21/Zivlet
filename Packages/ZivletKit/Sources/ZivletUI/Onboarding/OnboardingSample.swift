import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The practice file (P1-47): drawn by Zivlet at first use, so no image is bundled. A 512 × 320 PNG with a
/// gradient and the word "Practice".
public enum OnboardingSample {
    public static let fileName = "practice.png"
    static let width = 512
    static let height = 320

    public enum Failure: Error, Equatable {
        case folder, drawing, writing
    }

    /// `~/Library/Application Support/Zivlet/Practice`.
    public static var standardFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Zivlet/Practice", directoryHint: .isDirectory)
    }

    /// The sample in `folder`, drawn only when it is not there yet.
    public static func make(in folder: URL) throws(Failure) -> URL {
        let url = folder.appending(path: fileName, directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw .folder
        }
        guard let image = draw() else { throw .drawing }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw .writing }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw .writing }
        return url
    }

    static func draw() -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let colours = [
            CGColor(srgbRed: 0.16, green: 0.42, blue: 0.86, alpha: 1),
            CGColor(srgbRed: 0.55, green: 0.3, blue: 0.85, alpha: 1),
        ]
        if let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colours as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        drawWord("Practice", in: context)
        return context.makeImage()
    }

    private static func drawWord(_ word: String, in context: CGContext) {
        let font =
            CTFontCreateUIFontForLanguage(.system, 64, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 64, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: word, attributes: attributes))
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(
            x: (CGFloat(width) - bounds.width) / 2 - bounds.minX, y: (CGFloat(height) - bounds.height) / 2 - bounds.minY
        )
        CTLineDraw(line, context)
    }
}
