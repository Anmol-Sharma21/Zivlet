import CoreGraphics
import CoreText
import Foundation

/// The PDF fixtures of plan 18d, drawn at test time from the image fixtures' sentences: CoreText text pages (whose
/// Hindi text layer extracts in visual order, 17a L1), an image-only "scan", and a file that disallows copying.
public enum PDFFixtures {
    public enum Kind: String, CaseIterable, Sendable {
        case english, hindi, mixed, scan, noCopy

        /// The manifest fixture whose sentence the PDF carries.
        var fixture: String {
            switch self {
            case .english, .noCopy: "01_english"
            case .hindi: "03_hindi_kohinoor"
            case .mixed, .scan: "05_mixed"
            }
        }

        public var fileName: String { rawValue + ".pdf" }
    }

    /// US Letter in points.
    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// The ground truth of a PDF fixture.
    public static func text(of kind: Kind) throws -> String { try entry(kind.fixture).text }

    /// Writes one PDF and returns its URL.
    @discardableResult
    public static func render(_ kind: Kind, into folder: URL) throws -> URL {
        let url = folder.appending(path: kind.fileName, directoryHint: .notDirectory)
        let entry = try entry(kind.fixture)
        switch kind {
        case .scan: try write(url, pages: [.image(try OCRFixtures.draw(entry))])
        case .noCopy: try write(url, pages: [.text(entry)], allowsCopying: false)
        default: try write(url, pages: [.text(entry)])
        }
        return url
    }

    /// A PDF of `count` image-only pages of fixture 05, for page-by-page tests.
    @discardableResult
    public static func renderScans(count: Int, into folder: URL, name: String = "scans.pdf") throws -> URL {
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        let image = try OCRFixtures.draw(try entry(Kind.scan.fixture))
        try write(url, pages: Array(repeating: .image(image), count: count))
        return url
    }

    /// A PDF whose pages carry the given entries as CoreText text.
    @discardableResult
    public static func renderText(_ entries: [OCRFixtures.Entry], into folder: URL, name: String) throws -> URL {
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        try write(url, pages: entries.map { .text($0) })
        return url
    }

    enum Page {
        case text(OCRFixtures.Entry)
        case image(CGImage)
    }

    static func entry(_ name: String) throws -> OCRFixtures.Entry {
        guard let entry = try OCRFixtures.manifest().entries.first(where: { $0.name == name }) else {
            throw OCRFixtureError.renderFailed("no fixture \(name)")
        }
        return entry
    }

    /// Copying is refused through the permissions of an owner password; there is no user password, so the file
    /// opens unlocked.
    static func write(_ url: URL, pages: [Page], allowsCopying: Bool = true) throws {
        var box = page
        var info: [CFString: Any] = [kCGPDFContextCreator: "Zivlet tests"]
        if !allowsCopying {
            info[kCGPDFContextOwnerPassword] = "zivlet-owner"
            info[kCGPDFContextAllowsCopying] = false
        }
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw OCRFixtureError.renderFailed(url.lastPathComponent)
        }
        for content in pages {
            context.beginPDFPage(nil)
            switch content {
            case .text(let entry): try drawText(entry, in: context)
            case .image(let image): drawImage(image, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    static func drawText(_ entry: OCRFixtures.Entry, in context: CGContext) throws {
        let font = CTFontCreateWithName(entry.font as CFString, CGFloat(entry.size) / 2, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ]
        guard let text = CFAttributedStringCreate(nil, entry.text as CFString, attributes as CFDictionary) else {
            throw OCRFixtureError.renderFailed(entry.name)
        }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let area = page.insetBy(dx: 72, dy: 72)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: area, transform: nil), nil), context)
    }

    /// The image at 150 DPI near the top of the page.
    static func drawImage(_ image: CGImage, in context: CGContext) {
        let size = CGSize(width: CGFloat(image.width) * 72 / 150, height: CGFloat(image.height) * 72 / 150)
        let origin = CGPoint(x: 72, y: page.height - 72 - size.height)
        context.draw(image, in: CGRect(origin: origin, size: size))
    }
}
