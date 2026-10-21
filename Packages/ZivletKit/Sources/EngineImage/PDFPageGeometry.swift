import CoreGraphics
import Foundation
import ZivletEngineKit

/// Page size and drawing transform for an image placed on a PDF page (03b §6.2, P1-10): the page is the displayed
/// image at its DPI (72 when absent or nonsense), and the EXIF orientation is applied by the transform, so the
/// stored pixels (or JPEG bytes) are embedded as they are. Pure.
public enum PDFPageGeometry {
    public static let defaultDPI = 72.0
    static let pointsPerInch = 72.0

    /// A DPI property value, or 72 when it is missing, not a number, zero or negative.
    static func dpi(_ value: Any?) -> Double {
        guard let number = value as? Double, number.isFinite, number > 0 else { return defaultDPI }
        return number
    }

    /// `display` and the DPIs are already in displayed orientation.
    static func pageSize(display: PixelSize, dpiX: Double, dpiY: Double) -> CGSize {
        CGSize(
            width: Double(display.width) * pointsPerInch / dpi(dpiX),
            height: Double(display.height) * pointsPerInch / dpi(dpiY))
    }

    /// Orientations 5–8 turn the image by 90°, so width, height and their DPIs swap.
    static func pageSize(orientation: Int, stored: PixelSize, dpiX: Double, dpiY: Double) -> CGSize {
        guard orientation >= 5 else { return pageSize(display: stored, dpiX: dpiX, dpiY: dpiY) }
        return pageSize(display: PixelSize(width: stored.height, height: stored.width), dpiX: dpiY, dpiY: dpiX)
    }

    /// The transform to concatenate before drawing the stored image into the returned rectangle, so it shows upright
    /// on a page of `page` points (Quartz coordinates, origin bottom left).
    static func placement(orientation: Int, page: CGSize) -> (transform: CGAffineTransform, rect: CGRect) {
        let (w, h) = (page.width, page.height)
        let turned = orientation >= 5
        var transform = CGAffineTransform.identity
        switch orientation {
        case 3, 4: transform = transform.translatedBy(x: w, y: h).rotated(by: .pi)
        case 5, 8: transform = transform.translatedBy(x: w, y: 0).rotated(by: .pi / 2)
        case 6, 7: transform = transform.translatedBy(x: 0, y: h).rotated(by: -.pi / 2)
        default: break
        }
        switch orientation {
        case 2, 4: transform = transform.translatedBy(x: w, y: 0).scaledBy(x: -1, y: 1)
        case 5, 7: transform = transform.translatedBy(x: h, y: 0).scaledBy(x: -1, y: 1)
        default: break
        }
        return (transform, CGRect(x: 0, y: 0, width: turned ? h : w, height: turned ? w : h))
    }
}
