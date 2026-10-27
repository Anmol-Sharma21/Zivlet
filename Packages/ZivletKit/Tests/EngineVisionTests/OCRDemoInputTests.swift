import CoreGraphics
import EngineVision
import Foundation
import ImageIO
import OCRTestSupport
import Testing
import UniformTypeIdentifiers

/// The Copy Text demo's inputs (plan 18d D15, Scripts/demo-copy-text.sh): with `ZIVLET_OCR_DUMP=<folder>` it writes
/// fixture 05 as `05_mixed.png`, the mixed sentence as `mixed.pdf`, a blank `blank.png`, and the texts the demo must
/// read: `expected.txt` (both files, combined as Copy Text combines them) and `expected-1.txt`, `expected-2.txt`.
@Suite("Copy Text demo inputs", .enabled(if: ProcessInfo.processInfo.environment["ZIVLET_OCR_DUMP"] != nil))
struct OCRDemoInputTests {
    @Test func theInputsAndTheirExpectedTextsAreWritten() throws {
        let path = try #require(ProcessInfo.processInfo.environment["ZIVLET_OCR_DUMP"])
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let entry = try #require(OCRFixtures.entries.first { $0.name == "05_mixed" })
        try OCRFixtures.encoded(entry).write(to: folder.appending(path: "05_mixed.png"))
        try PDFFixtures.render(.mixed, into: folder)
        try Self.blankPNG(to: folder.appending(path: "blank.png"))
        let image = entry.text
        let pdf = try PDFFixtures.text(of: .mixed)
        let combined = TextAssembly.combine([
            FileText(name: "05_mixed.png", pages: [RecognizedPage(text: image)]),
            FileText(name: "mixed.pdf", pages: [RecognizedPage(text: pdf)]),
        ])
        try Data(combined.text.utf8).write(to: folder.appending(path: "expected.txt"))
        try Data((image + "\n").utf8).write(to: folder.appending(path: "expected-1.txt"))
        try Data((pdf + "\n").utf8).write(to: folder.appending(path: "expected-2.txt"))
    }

    /// A white 600 x 400 image: nothing to read.
    static func blankPNG(to url: URL) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
