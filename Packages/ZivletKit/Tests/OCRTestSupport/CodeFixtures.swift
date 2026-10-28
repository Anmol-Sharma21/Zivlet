import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Read QR's fixtures (plan 20b A7), made at test time by Core Image's own generators with payloads written for
/// Zivlet, and PDFs drawn with CoreGraphics. Nothing is downloaded.
public enum CodeFixtures {
    public static let link = "https://zivlet.app/test"
    public static let table = "Table 12"
    public static let ticket = "ZIVLET-0042"

    public enum Kind: Sendable {
        case qr, code128

        var filter: String {
            switch self {
            case .qr: "CIQRCodeGenerator"
            case .code128: "CICode128BarcodeGenerator"
            }
        }
    }

    /// A black-on-white code scaled up to whole pixels, with a white margin.
    public static func image(_ payload: String, kind: Kind = .qr, scale: CGFloat = 8) throws -> CGImage {
        guard let filter = CIFilter(name: kind.filter) else { throw OCRFixtureError.renderFailed(kind.filter) }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else {
            throw OCRFixtureError.renderFailed(payload)
        }
        let code = try CIContext().createCGImage(output, from: output.extent).orThrow(payload)
        return try padded(code, margin: Int(scale) * 4)
    }

    /// A white image of `width` × `height` with nothing on it.
    public static func blank(width: Int = 400, height: Int = 300) throws -> CGImage {
        let context = try canvas(width: width, height: height)
        return try context.makeImage().orThrow("blank")
    }

    /// Writes `image` as PNG.
    @discardableResult
    public static func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw OCRFixtureError.renderFailed(url.lastPathComponent) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw OCRFixtureError.renderFailed(url.lastPathComponent) }
        return url
    }

    /// A US Letter PDF with one image per page, drawn at 150 DPI near the top; with `userPassword` it is locked.
    @discardableResult
    public static func writePDF(_ pages: [CGImage], to url: URL, userPassword: String? = nil) throws -> URL {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        var info: [CFString: Any] = [kCGPDFContextCreator: "Zivlet tests"]
        if let userPassword {
            info[kCGPDFContextUserPassword] = userPassword
            info[kCGPDFContextOwnerPassword] = userPassword + "-owner"
        }
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
            throw OCRFixtureError.renderFailed(url.lastPathComponent)
        }
        for image in pages {
            context.beginPDFPage(nil)
            PDFFixtures.drawImage(image, in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// Two codes in one image, `first` above `second`.
    public static func stacked(_ first: CGImage, over second: CGImage) throws -> CGImage {
        let width = max(first.width, second.width)
        let context = try canvas(width: width, height: first.height + second.height)
        context.draw(second, in: CGRect(x: 0, y: 0, width: second.width, height: second.height))
        context.draw(first, in: CGRect(x: 0, y: second.height, width: first.width, height: first.height))
        return try context.makeImage().orThrow("stacked")
    }

    static func padded(_ image: CGImage, margin: Int) throws -> CGImage {
        let context = try canvas(width: image.width + 2 * margin, height: image.height + 2 * margin)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: margin, y: margin, width: image.width, height: image.height))
        return try context.makeImage().orThrow("padded")
    }

    static func canvas(width: Int, height: Int) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw OCRFixtureError.renderFailed("canvas") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }
}

extension Optional {
    fileprivate func orThrow(_ name: String) throws -> Wrapped {
        guard let self else { throw OCRFixtureError.renderFailed(name) }
        return self
    }
}
