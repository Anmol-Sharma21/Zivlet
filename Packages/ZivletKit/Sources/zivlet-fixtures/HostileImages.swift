import CoreGraphics
import Foundation
import ImageIO

/// Image files of the hostile corpus (P1-62) that need exact bytes or many frames: headers that claim enormous
/// canvases and a TIFF with thousands of pages. Written by Zivlet; the bodies carry no real pixels.
enum HostileImages {
    static let hugePNGSide: UInt32 = 60_000
    static let hugeWebPSide = 16_383
    static let tiffPages = 5_000

    static let all: [ImageRecipe] = [
        ImageRecipe(name: "huge-ihdr.png") { _, url throws(FixtureError) in try write(hugePNG(), to: url) },
        ImageRecipe(name: "huge-canvas.webp") { _, url throws(FixtureError) in try write(hugeWebP(), to: url) },
        ImageRecipe(name: "pages-5000.tiff") { _, url throws(FixtureError) in
            let page = try Canvas.draw(Paint((1, 1), space: ImageRecipes.srgb))
            try ImageFile.write(Array(repeating: page, count: tiffPages), type: "public.tiff", to: url)
        },
    ]

    /// A PNG signature and an IHDR chunk claiming 60,000 × 60,000 RGBA pixels; no image data follows.
    static func hugePNG() -> [UInt8] {
        let side = withUnsafeBytes(of: hugePNGSide.bigEndian, Array.init)
        let ihdr: [UInt8] = Array("IHDR".utf8) + side + side + [8, 6, 0, 0, 0]
        let length: [UInt8] = [0, 0, 0, 13]
        return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + length + ihdr
            + withUnsafeBytes(of: CRC32.checksum(ihdr).bigEndian, Array.init)
    }

    /// A lossless WebP header claiming 16,383 × 16,383 pixels with alpha, followed by a few junk bytes.
    static func hugeWebP() -> [UInt8] {
        let edge = UInt32(hugeWebPSide - 1)
        let bits = edge | (edge << 14) | (1 << 28)
        let vp8l: [UInt8] = [0x2F] + withUnsafeBytes(of: bits.littleEndian, Array.init) + [0, 0, 0]
        let chunk = Array("VP8L".utf8) + withUnsafeBytes(of: UInt32(vp8l.count).littleEndian, Array.init) + vp8l
        let body = Array("WEBP".utf8) + chunk
        return Array("RIFF".utf8) + withUnsafeBytes(of: UInt32(body.count).littleEndian, Array.init) + body
    }

    private static func write(_ bytes: [UInt8], to url: URL) throws(FixtureError) {
        do {
            try Data(bytes).write(to: url)
        } catch {
            throw .writing(url.lastPathComponent)
        }
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
