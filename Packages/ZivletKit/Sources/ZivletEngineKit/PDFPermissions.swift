/// What an encrypted PDF allows, in the bit positions of its `/P` entry (bit n of the PDF specification is
/// `1 << (n - 1)`). Revision 2 files have fewer bits; the shim reads them through qpdf, which fills these in by that
/// file's rules. A file that is not encrypted allows everything.
public struct PDFPermissions: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let printLowQuality = PDFPermissions(rawValue: 1 << 2)
    public static let modify = PDFPermissions(rawValue: 1 << 3)
    public static let copy = PDFPermissions(rawValue: 1 << 4)
    public static let annotate = PDFPermissions(rawValue: 1 << 5)
    public static let fillForms = PDFPermissions(rawValue: 1 << 8)
    public static let accessibility = PDFPermissions(rawValue: 1 << 9)
    public static let assemble = PDFPermissions(rawValue: 1 << 10)
    public static let printHighQuality = PDFPermissions(rawValue: 1 << 11)

    public static let all: PDFPermissions = [
        .printLowQuality, .modify, .copy, .annotate, .fillForms, .accessibility, .assemble, .printHighQuality,
    ]
}
