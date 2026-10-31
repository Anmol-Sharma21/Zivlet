import CoreGraphics
import Foundation
import PDFKit

/// PDFs that hold what pre-flight looks for (plan 20e D1), in our own bytes and words. Structure CoreGraphics never
/// writes is typed out through `raw`, so no test helper needs a C++ target of its own.
extension PDFFixtures {
    /// The one-page objects with extra catalog entries (and objects after them, numbered from 5).
    public static func objects(catalog: String = "", page: String = "", extra: [String] = []) -> [String] {
        [
            "<< /Type /Catalog /Pages 2 0 R \(catalog) >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R \(page) >>",
            "<< /Length 0 >>\nstream\n\nendstream",
        ] + extra
    }

    /// A real AcroForm: a text field holding a value and a signature field, both on the page.
    @discardableResult
    public static func acroForm(in dir: URL, name: String = "acroform.pdf") throws -> URL {
        let text =
            "<< /Type /Annot /Subtype /Widget /FT /Tx /T (fullName) /V (Zivlet) /Rect [72 600 312 628] /P 3 0 R >>"
        let signature = "<< /Type /Annot /Subtype /Widget /FT /Sig /T (signedBy) /Rect [72 500 312 528] /P 3 0 R >>"
        let form = objects(
            catalog: "/AcroForm << /Fields [5 0 R 6 0 R] >>", page: "/Annots [5 0 R 6 0 R]", extra: [text, signature])
        return try raw(in: dir, name: name, objects: form)
    }

    /// A page with a text field and a signature field as PDFKit writes them: widgets on the page, and no `/AcroForm`
    /// in the catalog (seen on this SDK).
    @discardableResult
    public static func form(in dir: URL, name: String = "form.pdf") throws -> URL {
        let base = try plain(in: dir, name: "form-base.pdf", pages: 1)
        guard let document = PDFDocument(url: base), let page = document.page(at: 0) else {
            throw FixtureError.noContext
        }
        page.addAnnotation(widget(.text, name: "fullName", y: 600))
        page.addAnnotation(widget(.signature, name: "signedBy", y: 500))
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        guard document.write(to: url) else { throw FixtureError.noContext }
        return url
    }

    /// A file that opens with the empty user password and restricts what it allows (CoreGraphics; `keyLength` picks
    /// RC4 at 40 and AES-128 at 128).
    @discardableResult
    public static func restrictionsOnly(
        in dir: URL, name: String = "restricted.pdf", owner: String, keyLength: Int = 128
    ) throws -> URL {
        let url = dir.appending(path: name, directoryHint: .notDirectory)
        try write(
            to: url, pages: 2,
            info: [
                kCGPDFContextOwnerPassword: owner, kCGPDFContextEncryptionKeyLength: keyLength,
                kCGPDFContextAllowsCopying: false, kCGPDFContextAllowsPrinting: false,
            ])
        return url
    }

    /// A one-page file whose first object says it is linearized, with the true file size in `/L`.
    @discardableResult
    public static func linearized(in dir: URL, name: String = "linearized.pdf") throws -> URL {
        let placeholder = "0000000000"
        let objects = ["<< /Linearized 1 /L \(placeholder) >>"] + onePageObjects.map(shiftedByOne)
        let url = try raw(in: dir, name: name, objects: objects, root: 2)
        let size = String(format: "%010d", try Data(contentsOf: url).count)
        let text = try String(contentsOf: url, encoding: .utf8)
        try Data(text.replacingOccurrences(of: placeholder, with: size).utf8).write(to: url)
        return url
    }

    /// An AES-128 file whose crypt filters CoreGraphics named are replaced by `/Identity` (no cipher at all). Its
    /// offsets shift, so qpdf reads it by rebuilding the cross-reference table.
    @discardableResult
    public static func identityCrypt(in dir: URL, name: String = "identity.pdf", user: String) throws -> URL {
        let url = try encrypted(in: dir, name: name, keyLength: 128, user: user, owner: user + "-owner")
        let bytes = try Data(contentsOf: url)
        let patched = ["/StmF /StdCF", "/StrF /StdCF"].reduce(bytes) { data, pattern in
            replacing(
                Data(pattern.utf8), in: data,
                with: Data(pattern.replacingOccurrences(of: "/StdCF", with: "/Identity").utf8))
        }
        try patched.write(to: url)
        return url
    }

    /// The one-page objects, each object number raised by one, for a file with an object before them.
    private static func shiftedByOne(_ object: String) -> String {
        object.replacingOccurrences(of: "/Pages 2 0 R", with: "/Pages 3 0 R")
            .replacingOccurrences(of: "/Kids [3 0 R]", with: "/Kids [4 0 R]")
            .replacingOccurrences(of: "/Parent 2 0 R", with: "/Parent 3 0 R")
            .replacingOccurrences(of: "/Contents 4 0 R", with: "/Contents 5 0 R")
    }

    private static func replacing(_ pattern: Data, in data: Data, with replacement: Data) -> Data {
        guard let range = data.range(of: pattern) else { return data }
        return data.replacingCharacters(in: range, with: replacement)
    }

    private static func widget(_ type: PDFAnnotationWidgetSubtype, name: String, y: CGFloat) -> PDFAnnotation {
        let bounds = CGRect(x: 72, y: y, width: 240, height: 28)
        let annotation = PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
        annotation.widgetFieldType = type
        annotation.fieldName = name
        return annotation
    }
}

extension Data {
    /// A copy with `range` replaced, so a fixture never mutates what it read.
    fileprivate func replacingCharacters(in range: Range<Data.Index>, with replacement: Data) -> Data {
        self[startIndex..<range.lowerBound] + replacement + self[range.upperBound..<endIndex]
    }
}
