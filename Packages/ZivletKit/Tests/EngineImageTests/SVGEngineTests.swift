import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit
import zlib

@testable import EngineImage

/// SVG sources written at test time, and gzip for `.svgz`.
enum SVGFixture {
    static let drawing = #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
        <rect width="120" height="80" fill="#0a0"/><circle cx="60" cy="40" r="30" fill="#00f"/></svg>
        """#

    static func write(_ text: String, named name: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    static func writeGzipped(_ text: String, named name: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try gzip(Data(text.utf8)).write(to: url)
        return url
    }

    /// gzip framing (windowBits 31) around deflate, level 9.
    static func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let size = Int32(MemoryLayout<z_stream>.size)
        try #require(deflateInit2_(&stream, 9, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, size) == Z_OK)
        defer { deflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(data.count))) + 64)
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { out in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(out.count)
                return deflate(&stream, Z_FINISH)
            }
        }
        try #require(status == Z_STREAM_END)
        return Data(output.prefix(Int(stream.total_out)))
    }

    static func isMostlyBlue(_ rgb: [UInt8]) -> Bool { rgb[2] > 200 && rgb[0] < 60 && rgb[1] < 60 }
    static func isWhite(_ rgb: [UInt8]) -> Bool { rgb.allSatisfy { $0 > 240 } }
}

@Suite("SVG input (D-M4-6): seven raster targets and raster-in-PDF")
struct SVGEngineTests {
    let run = ImageRun()

    func convert(_ make: @escaping @Sendable (URL) throws -> URL, to target: FormatID) async throws
        -> (plan: ExecutionPlan, output: URL)
    {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await run.convert(try await offPool { try make(dir) }, .svg, to: target, in: dir)
        return (plan, output.url)
    }

    @Test(arguments: [FormatID.jpg, .png, .webp, .heic, .tiff, .avif, .bmp])
    func rendersAtTwiceTheIntrinsicSize(target: FormatID) async throws {
        let (_, output) = try await convert(
            { try SVGFixture.write(SVGFixture.drawing, named: "d.svg", in: $0) }, to: target)
        #expect(try ImageReader.probe(output).pixelSize == PixelSize(width: 240, height: 160))
        #expect(SVGFixture.isMostlyBlue(try ImageFixture.pixel(output, x: 120, y: 80)))
        #expect(try ImageFixture.pixel(output, x: 4, y: 4)[1] > 120)
    }

    @Test func pdfIsOnePageAtTheDrawingSizeWithAnImage() async throws {
        let (plan, output) = try await convert(
            { try SVGFixture.write(SVGFixture.drawing, named: "d.svg", in: $0) }, to: .pdf)
        let document = try #require(CGPDFDocument(output as CFURL))
        #expect(document.numberOfPages == 1)
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 120, height: 80))
        #expect(plan.notes == [.svgRasterizedInPDF])
    }

    @Test func transparentDrawingsAreFlattenedForOpaqueTargetsAndSaySo() async throws {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="5" height="10"/></svg>"#
        let (plan, output) = try await convert({ try SVGFixture.write(svg, named: "t.svg", in: $0) }, to: .jpg)
        #expect(plan.notes == [.alphaFlattened])
        #expect(SVGFixture.isWhite(try ImageFixture.pixel(output, x: 15, y: 10)))
        let png = try await convert({ try SVGFixture.write(svg, named: "t.svg", in: $0) }, to: .png)
        #expect(png.plan.notes.isEmpty)
        #expect(try ImageFixture.properties(png.output)[kCGImagePropertyHasAlpha] as? Bool == true)
    }

    @Test func svgzIsGunzippedWithinLimits() async throws {
        let (_, output) = try await convert(
            { try SVGFixture.writeGzipped(SVGFixture.drawing, named: "d.svgz", in: $0) }, to: .png)
        #expect(try ImageReader.probe(output).pixelSize == PixelSize(width: 240, height: 160))
    }

    @Test func aGzipBombIsRefused() async throws {
        let dir = try ImageFixture.directory()
        let bomb = try SVGFixture.writeGzipped(String(repeating: " ", count: 80 << 20), named: "b.svgz", in: dir)
        await #expect(throws: JobError.unsupportedInput(.tooLarge)) {
            try await run.convert(bomb, .svg, to: .png, in: dir)
        }
    }

    @Test func aHugeDrawingIsCappedAtTheLongestEdge() async throws {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="50000"/>"#
        let dir = try ImageFixture.directory()
        let input = try InputItem(url: try SVGFixture.write(svg, named: "h.svg", in: dir), format: .svg, byteCount: 1)
        let request = try JobRequest(input: input, operation: .convert(.png), destination: dir)
        let plan = try await run.engine.prepare(request, workspace: JobWorkspace(job: request.id, stagedFile: dir))
        #expect(plan.stages[0].image?.expectedSize == PixelSize(width: 8192, height: 4096))
    }

    @Test func externalFilesAreNeverRead() async throws {
        let dir = try ImageFixture.directory()
        let red = try await offPool { try ImageFixture.opaque(.png, in: dir) }
        let svg =
            ##"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="#fff"/>"##
            + #"<image href="\#(red.path)" width="20" height="20"/></svg>"#
        let (_, output) = try await run.convert(
            try SVGFixture.write(svg, named: "x.svg", in: dir), .svg, to: .png, in: dir)
        #expect(SVGFixture.isWhite(try ImageFixture.pixel(output.url, x: 5, y: 20)))
    }

    @Test(arguments: ["hello", #"<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0"/>"#])
    func notAnSVGIsUnreadable(text: String) async throws {
        let dir = try ImageFixture.directory()
        await #expect(throws: JobError.unsupportedInput(.unreadable)) {
            try await run.convert(try SVGFixture.write(text, named: "n.svg", in: dir), .svg, to: .png, in: dir)
        }
    }

    @Test func aTruncatedSvgzIsUnreadable() async throws {
        let dir = try ImageFixture.directory()
        let whole = try SVGFixture.gzip(Data(SVGFixture.drawing.utf8))
        let url = dir.appending(path: "cut.svgz")
        try whole.prefix(whole.count / 2).write(to: url)
        await #expect(throws: JobError.unsupportedInput(.unreadable)) {
            try await run.convert(url, .svg, to: .png, in: dir)
        }
    }

    /// A sparse file one byte past the cap: refused from its size, never read into memory.
    @Test func aFileOverTheInputCapIsRefusedUnread() throws {
        let dir = try ImageFixture.directory()
        let url = dir.appending(path: "big.svg")
        try #require(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SVGSource.maxBytes + 1))
        try handle.close()
        #expect(throws: JobError.unsupportedInput(.tooLarge)) { try SVGSource.read(url) }
    }

    @Test func theRasterSizeMatchesTheRenderer() {
        let geometry = SVGGeometry(width: 120.4, height: 80)
        #expect(geometry.rasterSize == PixelSize(width: 241, height: 160))
        #expect(geometry.pageSize == PixelSize(width: 120, height: 80))
        #expect(SVGGeometry(width: 9000, height: 10).rasterSize == PixelSize(width: 8192, height: 10))
    }
}
