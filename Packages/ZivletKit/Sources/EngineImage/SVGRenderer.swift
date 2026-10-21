import CZivletSVG
import CoreGraphics
import Foundation
import ZivletCore
import ZivletEngineKit

/// An SVG's intrinsic size in CSS pixels and what zivlet-svg makes of it (D-M4-6, 03b §6.4): rendered at 2×, the
/// longest edge capped at 8,192 pixels (67 MP, under the 200 MP decode cap); a PDF page is one point per CSS pixel.
/// `size(scale:maxEdge:)` mirrors the crate's `pixels` rounding exactly, so the plan knows the output size. Pure.
public struct SVGGeometry: Sendable, Equatable {
    public static let scale: Float = 2
    public static let maxEdge = 8_192

    public let width: Float
    public let height: Float

    public init(width: Float, height: Float) {
        self.width = width
        self.height = height
    }

    var rasterSize: PixelSize { size(scale: Self.scale, maxEdge: Self.maxEdge) }

    var pageSize: PixelSize {
        PixelSize(width: max(Int(Double(width).rounded()), 1), height: max(Int(Double(height).rounded()), 1))
    }

    func size(scale: Float, maxEdge: Int) -> PixelSize {
        let longest = max(width, height)
        let fitted = longest * scale > Float(maxEdge) ? Float(maxEdge) / longest : scale
        return PixelSize(
            width: Self.pixels(width, fitted, maxEdge), height: Self.pixels(height, fitted, maxEdge))
    }

    /// `edge * scale` rounded up, never past `maxEdge` (float error must not add a pixel).
    static func pixels(_ edge: Float, _ scale: Float, _ maxEdge: Int) -> Int {
        let exact = Double(edge) * Double(scale)
        let rounded = max((exact - 1e-3).rounded(.up), 0)
        return Int(min(rounded, Double(maxEdge)))
    }
}

/// Calls into zivlet-svg (resvg; only `data:` image hrefs resolve, so no file or network is read).
enum SVGRenderer {
    static let typeIdentifier = "public.svg-image"

    /// Intrinsic size without rendering; an SVG is taken to have transparency.
    static func probe(_ url: URL) throws(JobError) -> ImageProbe {
        let data = try SVGSource.read(url)
        var width: Float = 0
        var height: Float = 0
        let code = data.withUnsafeBytes { raw in
            zivlet_svg_size(raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &width, &height)
        }
        guard code == Int32(ZIVLET_SVG_OK) else { throw error(code) }
        let geometry = SVGGeometry(width: width, height: height)
        let size = geometry.rasterSize
        guard width.isFinite, height.isFinite, size.width > 0, size.height > 0 else {
            throw .unsupportedInput(.unreadable)
        }
        return ImageProbe(
            typeIdentifier: typeIdentifier, frameCount: 1, pixelSize: size, orientation: 1, hasAlpha: true,
            svg: geometry)
    }

    static func error(_ code: Int32) -> JobError {
        switch code {
        case Int32(ZIVLET_SVG_PARSE), Int32(ZIVLET_SVG_SIZE): .unsupportedInput(.unreadable)
        case Int32(ZIVLET_SVG_ALLOC): .writeFailed("There wasn't enough memory to draw the SVG.")
        default: .internalInvariant("zivlet-svg refused its arguments (\(code))")
        }
    }
}

/// Premultiplied RGBA pixels owned by zivlet-svg. Freed in `deinit`, unless `image()` hands them to a `CGImage`,
/// whose data provider then frees them when Quartz lets go.
struct SVGBitmap: ~Copyable {
    private let storage: UnsafeMutablePointer<ZivletSvgImage>

    private init(storage: UnsafeMutablePointer<ZivletSvgImage>) { self.storage = storage }

    static func render(_ data: Data, options: SVGRasterOptions) throws(JobError) -> SVGBitmap {
        let storage = UnsafeMutablePointer<ZivletSvgImage>.allocate(capacity: 1)
        storage.initialize(to: ZivletSvgImage(width: 0, height: 0, rgba: nil))
        let code = data.withUnsafeBytes { raw in
            zivlet_svg_render(
                raw.bindMemory(to: UInt8.self).baseAddress, raw.count, options.scale, UInt32(options.maxEdge), storage)
        }
        guard code == Int32(ZIVLET_SVG_OK), storage.pointee.rgba != nil else {
            zivlet_svg_free(storage)
            storage.deallocate()
            throw SVGRenderer.error(code)
        }
        return SVGBitmap(storage: storage)
    }

    deinit {
        zivlet_svg_free(storage)
        storage.deallocate()
    }

    var size: PixelSize { PixelSize(width: Int(storage.pointee.width), height: Int(storage.pointee.height)) }

    /// An sRGB, premultiplied-last `CGImage` over the pixels, without copying them.
    consuming func image() throws(JobError) -> CGImage {
        let storage = self.storage
        let size = self.size
        discard self
        guard let rgba = storage.pointee.rgba,
            let provider = CGDataProvider(
                dataInfo: storage, data: rgba, size: size.width * size.height * 4,
                releaseData: { info, _, _ in
                    guard let image = info?.assumingMemoryBound(to: ZivletSvgImage.self) else { return }
                    zivlet_svg_free(image)
                    image.deallocate()
                })
        else {
            zivlet_svg_free(storage)
            storage.deallocate()
            throw .internalInvariant("cannot wrap the rendered SVG")
        }
        guard
            let image = CGImage(
                width: size.width, height: size.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: size.width * 4, space: RGBAFrame.srgb,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw .internalInvariant("cannot make an image of the rendered SVG") }
        return image
    }
}
