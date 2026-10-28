import CoreGraphics
import CoreText
import Foundation

/// PDFs written at test time with CoreGraphics, in our own words (plan 20d C4): never a downloaded file. On this SDK
/// CoreGraphics encrypts with RC4 at a 40-bit key and with AES-128 at a 128-bit key (plan 20 §3.2); it cannot write
/// RC4-128 or AES-256, and it refuses a password that is not ASCII.
public enum PDFFixtures {
    public enum FixtureError: Error, Equatable {
        /// CoreGraphics gave no PDF context (for example for a non-ASCII password).
        case noContext
    }

    /// The page size of every fixture: US Letter in points.
    public static let pageSize = CGSize(width: 612, height: 792)

    /// A plain PDF of `pages` pages, each with one line of text.
    @discardableResult
    public static func plain(in dir: URL, name: String = "plain.pdf", pages: Int = 2) throws -> URL {
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        try write(to: url, pages: pages, info: [:])
        return url
    }

    /// A PDF CoreGraphics encrypts with `user` and `owner`: RC4 when `keyLength` is 40, AES-128 when it is 128.
    @discardableResult
    public static func encrypted(
        in dir: URL, name: String = "locked.pdf", keyLength: Int, user: String, owner: String, pages: Int = 2
    ) throws -> URL {
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        let info: [CFString: Any] = [
            kCGPDFContextUserPassword: user, kCGPDFContextOwnerPassword: owner,
            kCGPDFContextEncryptionKeyLength: keyLength,
        ]
        try write(to: url, pages: pages, info: info)
        return url
    }

    /// A hand-made PDF from numbered object bodies (object 1 first) and extra trailer entries, with a correct cross
    /// reference table; for structures CoreGraphics never writes (an unknown security handler, say).
    @discardableResult
    public static func raw(in dir: URL, name: String, objects: [String], trailer: String = "") throws -> URL {
        var body = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(body.utf8.count)
            body += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = body.utf8.count
        body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        body += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        body += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R \(trailer) >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        try Data(body.utf8).write(to: url)
        return url
    }

    /// A one-page PDF whose cross-reference offset points nowhere: qpdf reads it by rebuilding the table, with
    /// warnings.
    @discardableResult
    public static func brokenCrossReference(in dir: URL, name: String = "broken.pdf") throws -> URL {
        let url = try raw(in: dir, name: name, objects: onePageObjects)
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let marker = text.range(of: "startxref\n") else { return url }
        let broken = text[..<marker.upperBound] + "9\n%%EOF\n"
        try Data(broken.utf8).write(to: url)
        return url
    }

    /// The objects of a one-page document for `raw`: catalog 1, pages 2, page 3 with an empty content stream 4.
    public static let onePageObjects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
        "<< /Length 0 >>\nstream\n\nendstream",
    ]

    private static func write(to url: URL, pages: Int, info: [CFString: Any]) throws {
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw FixtureError.noContext
        }
        for page in 1...max(1, pages) {
            context.beginPDFPage(nil)
            draw("Zivlet test page \(page) of \(pages)", in: context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func draw(_ text: String, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributed = NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 72, y: pageSize.height - 108)
        CTLineDraw(line, context)
    }
}
