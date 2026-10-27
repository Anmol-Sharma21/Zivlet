import CoreGraphics
import PDFKit

/// Draws one PDF page for recognition: the crop box at 300 DPI on white, the page's rotation honoured, the longest
/// side capped at 8192 px and the area at 16 MP like the image decode limits (P2-12).
public enum PageRenderer {
    public static let dpi: CGFloat = 300
    public static let maximumSide: CGFloat = 8192
    public static let maximumPixels: CGFloat = 16_000_000

    /// The bitmap size for a page of `points`, scaled down to the caps.
    public static func pixelSize(points: CGSize, dpi: CGFloat = dpi) -> CGSize {
        guard points.width > 0, points.height > 0 else { return .zero }
        let wanted = dpi / 72
        let bySide = maximumSide / max(points.width, points.height)
        let byArea = (maximumPixels / (points.width * points.height)).squareRoot()
        let scale = min(wanted, bySide, byArea)
        return CGSize(width: (points.width * scale).rounded(.down), height: (points.height * scale).rounded(.down))
    }

    public static func render(_ page: PDFPage) throws(TextError) -> CGImage {
        guard let pdfPage = page.pageRef else { throw .unreadable }
        let box = page.bounds(for: .cropBox)
        let turned = page.rotation % 180 != 0
        let points = turned ? CGSize(width: box.height, height: box.width) : box.size
        let pixels = pixelSize(points: points)
        guard pixels.width >= 1, pixels.height >= 1, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw .unreadable }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixels))
        context.scaleBy(x: pixels.width / points.width, y: pixels.height / points.height)
        let target = CGRect(origin: .zero, size: points)
        context.concatenate(pdfPage.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(pdfPage)
        guard let image = context.makeImage() else { throw .unreadable }
        return image
    }
}
