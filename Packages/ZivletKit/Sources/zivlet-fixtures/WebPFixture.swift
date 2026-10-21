import CWebP
import CoreGraphics
import Foundation

/// A lossless WebP input (ImageIO reads WebP but cannot write it), encoded with the vendored libwebp.
enum WebPFixture {
    static func write(_ image: CGImage, to url: URL) throws(FixtureError) {
        let width = image.width
        let height = image.height
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride,
                    space: ImageRecipes.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw .drawing(url.lastPathComponent) }
        try encode(pixels, width: width, height: height, stride: stride, to: url)
    }

    private static func encode(_ rgba: [UInt8], width: Int, height: Int, stride: Int, to url: URL)
        throws(FixtureError)
    {
        var output: UnsafeMutablePointer<UInt8>?
        let size = rgba.withUnsafeBufferPointer { buffer in
            WebPEncodeLosslessRGBA(buffer.baseAddress, Int32(width), Int32(height), Int32(stride), &output)
        }
        defer { WebPFree(output) }
        guard size > 0, let output else { throw .writing(url.lastPathComponent) }
        do {
            try Data(bytes: output, count: size).write(to: url)
        } catch {
            throw .writing(url.lastPathComponent)
        }
    }
}
