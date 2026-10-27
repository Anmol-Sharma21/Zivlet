import CoreGraphics
import EngineVision
import Foundation
import ImageIO
import Synchronization
import TestSupport
import UniformTypeIdentifiers

public enum TextFileError: Error {
    case notWritten(String)
}

/// Unwraps or throws, for helpers outside a test function.
func require<T>(_ value: T?) throws -> T {
    guard let value else { throw TextFileError.notWritten("nil") }
    return value
}

/// Answers each call with the next text of its list (the last one repeats) and records the image sizes.
public final class ScriptedRecognizer: TextRecognizing {
    let texts: [String]
    let delay: Duration
    public let sizes = Mutex<[CGSize]>([])

    public init(_ texts: [String], delay: Duration = .zero) {
        self.texts = texts
        self.delay = delay
    }

    public var calls: Int { sizes.withLock { $0.count } }

    public func recognize(_ image: CGImage, languages: [LanguageTag]) async throws(TextError) -> RecognizedPage {
        let index = sizes.withLock { sizes in
            sizes.append(CGSize(width: image.width, height: image.height))
            return sizes.count - 1
        }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if Task.isCancelled { throw .cancelled }
        return RecognizedPage(text: texts[min(index, texts.count - 1)])
    }
}

/// Image files for the text tests, written with ImageIO into a temporary folder.
public enum TextFiles {
    public static func png(_ name: String, in dir: TempDir, width: Int = 32, height: Int = 24) throws -> URL {
        let url = dir.url.appending(path: name)
        let space = try require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try require(context.makeImage())
        let destination = try require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TextFileError.notWritten(name) }
        return url
    }

    /// A PNG whose IHDR claims `width` × `height`, with an empty IDAT and an IEND: a header without the pixels.
    public static func pngHeader(_ name: String, in dir: TempDir, width: UInt32, height: UInt32) throws -> URL {
        var ihdr = Data("IHDR".utf8)
        for value in [width, height] { withUnsafeBytes(of: value.bigEndian) { ihdr.append(contentsOf: $0) } }
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])
        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        withUnsafeBytes(of: UInt32(13).bigEndian) { file.append(contentsOf: $0) }
        file.append(ihdr)
        withUnsafeBytes(of: crc32(ihdr).bigEndian) { file.append(contentsOf: $0) }
        for chunk in [Data("IDAT".utf8) + Data([0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]), Data("IEND".utf8)] {
            withUnsafeBytes(of: UInt32(chunk.count - 4).bigEndian) { file.append(contentsOf: $0) }
            file.append(chunk)
            withUnsafeBytes(of: crc32(chunk).bigEndian) { file.append(contentsOf: $0) }
        }
        let url = dir.url.appending(path: name)
        try file.write(to: url)
        return url
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
        }
        return ~crc
    }
}
