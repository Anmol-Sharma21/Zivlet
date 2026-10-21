import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// Images drawn with Core Graphics at test time (P1-60 subset): 40 × 20, left half red, right half blue.
enum ImageFixture {
    static let size = PixelSize(width: 40, height: 20)
    static let date = "2026:10:21 12:00:00"
    /// A 1 × 1 lossless WebP with alpha (ImageIO decodes WebP but cannot encode it).
    static let webp = "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=="

    static func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Left half: opaque red, or fully transparent when `alpha`. Right half: opaque blue.
    static func draw(space: CGColorSpace, bits: Int = 8, alpha: Bool = false) throws -> CGImage {
        let info: UInt32 =
            space.model == .cmyk
            ? CGImageAlphaInfo.none.rawValue
            : (alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
                | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
        let context = try #require(
            CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: bits, bytesPerRow: 0, space: space,
                bitmapInfo: info))
        let red = space.model == .cmyk ? [0, 1, 1, 0, 1] : [1, 0, 0, 1]
        let blue = space.model == .cmyk ? [1, 1, 0, 0, 1] : [0, 0, 1, 1]
        context.setFillColor(try #require(CGColor(colorSpace: space, components: blue.map { CGFloat($0) })))
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        if !alpha {
            context.setFillColor(try #require(CGColor(colorSpace: space, components: red.map { CGFloat($0) })))
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        return try #require(context.makeImage())
    }

    static func write(
        _ images: [CGImage], as format: FormatID, to url: URL, properties: [CFString: Any] = [:]
    ) throws {
        let type = FormatRegistry.standard.format(format).contentTypes[0] as CFString
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, images.count, nil))
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        try #require(CGImageDestinationFinalize(destination), "could not write \(format)")
    }

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)

    /// An opaque sRGB image with an EXIF capture date, in any ImageIO-writable source format (WebP is embedded).
    static func opaque(_ format: FormatID, in dir: URL) throws -> URL {
        let url = dir.appending(path: "source.\(format.rawValue)")
        if format == .webp {
            try #require(Data(base64Encoded: webp)).write(to: url)
            return url
        }
        if format == .svg {
            try Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"/>"#.utf8).write(to: url)
            return url
        }
        let exif = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: date]]
        try write([draw(space: try #require(srgb))], as: format, to: url, properties: exif)
        return url
    }

    static func alphaPNG(in dir: URL) throws -> URL {
        let url = dir.appending(path: "alpha.png")
        try write([draw(space: try #require(srgb), alpha: true)], as: .png, to: url)
        return url
    }

    static func rotatedJPEG(in dir: URL) throws -> URL {
        let url = dir.appending(path: "rotated.jpg")
        try write([draw(space: try #require(srgb))], as: .jpg, to: url, properties: [kCGImagePropertyOrientation: 6])
        return url
    }

    static func deepP3PNG(in dir: URL) throws -> URL {
        let url = dir.appending(path: "deep.png")
        try write([draw(space: try #require(CGColorSpace(name: CGColorSpace.displayP3)), bits: 16)], as: .png, to: url)
        return url
    }

    static func cmykJPEG(in dir: URL) throws -> URL {
        let url = dir.appending(path: "cmyk.jpg")
        try write([draw(space: try #require(CGColorSpace(name: CGColorSpace.genericCMYK)))], as: .jpg, to: url)
        return url
    }

    static func pagedTIFF(_ pages: Int, in dir: URL) throws -> URL {
        let url = dir.appending(path: "pages.tiff")
        let page = try draw(space: try #require(srgb))
        try write(Array(repeating: page, count: pages), as: .tiff, to: url)
        return url
    }

    /// A PNG header that claims 60,000 × 60,000 pixels; nothing after it decodes.
    static func hugePNGHeader(in dir: URL) throws -> URL {
        let url = dir.appending(path: "huge.png")
        let side: [UInt8] = [0x00, 0x00, 0xEA, 0x60]
        let ihdr: [UInt8] = Array("IHDR".utf8) + side + side + [8, 6, 0, 0, 0]
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + ihdr
        bytes += withUnsafeBytes(of: CRC32.checksum(ihdr).bigEndian, Array.init)
        try Data(bytes).write(to: url)
        return url
    }

    /// The colour of one pixel (x from the left, y from the top), as sRGB 0…255.
    static func pixel(_ url: URL, x: Int, y: Int) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = try #require(srgb)
        let context = try #require(
            CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return Array(rgba.prefix(3))
    }

    static func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }
}

/// CRC-32 (IEEE), for the crafted PNG chunk.
enum CRC32 {
    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

/// Fixture writes run on GCD too: concurrent AVIF encodes on the cooperative pool deadlock (index D-M3-10).
func offPool<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result { try body() }) }
    }
}

/// Runs one conversion through the engine into `dir`, returning the plan and the staged output.
struct ImageRun {
    let engine: ImageEngine

    init(engine: ImageEngine = ImageEngine()) { self.engine = engine }

    func convert(
        _ url: URL, _ format: FormatID, to target: FormatID, in dir: URL, context: ExecutionContext = ExecutionContext()
    ) async throws -> (plan: ExecutionPlan, output: StagedOutput) {
        let input = try InputItem(url: url, format: format, byteCount: 1)
        let request = try JobRequest(input: input, operation: .convert(target), destination: dir)
        let workspace = JobWorkspace(job: request.id, stagedFile: dir.appending(path: ".zivlet-\(request.id)"))
        let plan = try await engine.prepare(request, workspace: workspace)
        let output = try await engine.execute(plan, context: context)
        try await engine.verify(output, plan: plan)
        return (plan, output)
    }
}
