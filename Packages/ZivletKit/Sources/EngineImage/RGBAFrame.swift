import Accelerate
import CWebP
import CoreGraphics
import Foundation
import ZivletCore
import ZivletEngineKit

/// One frame as 8-bit RGBA with straight (not premultiplied) alpha, the layout libwebp imports. Opaque frames are
/// RGBX. The colour space is the frame's own RGB space, or sRGB for grey, CMYK and anything Quartz cannot draw into.
struct RGBAFrame {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    let bytes: [UInt8]
    let size: PixelSize
    let alpha: Bool

    static func space(for image: CGImage) -> CGColorSpace {
        guard let space = image.colorSpace, space.model == .rgb, space.supportsOutput else { return srgb }
        return space
    }

    /// Draws `image` scaled to `canvas` into `space`; un-premultiplies when `alpha`.
    init(_ image: CGImage, canvas: PixelSize, space: CGColorSpace, alpha: Bool) throws(JobError) {
        let (width, height) = (canvas.width, canvas.height)
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                    space: space, bitmapInfo: info.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard alpha else { return true }
            var buffer = vImage_Buffer(
                data: raw.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                rowBytes: rowBytes)
            return vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        guard drawn else { throw .internalInvariant("cannot draw a frame for the WebP encoder") }
        self.bytes = bytes
        self.size = canvas
        self.alpha = alpha
    }

    /// A `WebPPicture` holding these pixels for `body`; freed afterwards on every path.
    func withPicture<T>(_ body: (inout WebPPicture) throws(JobError) -> T) throws(JobError) -> T {
        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw .internalInvariant("libwebp picture version mismatch") }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(size.width)
        picture.height = Int32(size.height)
        picture.use_argb = 1
        let stride = Int32(size.width * 4)
        let imported = bytes.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            return alpha
                ? WebPPictureImportRGBA(&picture, base, stride) : WebPPictureImportRGBX(&picture, base, stride)
        }
        guard imported != 0 else { throw WebPEncodeFailure.error(picture.error_code) }
        return try body(&picture)
    }
}
