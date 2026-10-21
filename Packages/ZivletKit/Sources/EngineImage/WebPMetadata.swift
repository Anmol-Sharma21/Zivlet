import CoreGraphics
import Foundation
import ImageIO
import ZivletEngineKit

/// The source metadata a WebP carries (03b §6.2: metadata kept): whether to embed the colour profile the pixels are
/// drawn in, the EXIF block and the XMP packet, all saying orientation 1 and the output's pixel size, since the
/// pixels are written upright.
struct WebPMetadata: Sendable, Equatable {
    static let none = WebPMetadata(keepsProfile: false, exif: nil, xmp: nil)

    let keepsProfile: Bool
    let exif: Data?
    let xmp: Data?

    static func read(_ source: CGImageSource, index: Int, output: PixelSize, options: WebPOptions) -> WebPMetadata {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let hasEXIF =
            properties[kCGImagePropertyExifDictionary] != nil || properties[kCGImagePropertyGPSDictionary] != nil
        return WebPMetadata(
            keepsProfile: options.keepICC && properties[kCGImagePropertyProfileName] != nil,
            exif: options.keepEXIF && hasEXIF ? EXIFBlock.make(properties, output: output) : nil,
            xmp: options.keepXMP ? xmp(source, index, output: output) : nil)
    }

    private static func xmp(_ source: CGImageSource, _ index: Int, output: PixelSize) -> Data? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
            (CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag])?.isEmpty == false,
            let mutable = CGImageMetadataCreateMutableCopy(metadata)
        else { return nil }
        let facts: [(CFString, CFString, Int)] = [
            (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, output.width),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, output.height),
        ]
        for (dictionary, key, value) in facts {
            CGImageMetadataSetValueMatchingImageProperty(mutable, dictionary, key, value as CFNumber)
        }
        return CGImageMetadataCreateXMPData(mutable, nil) as Data?
    }
}

/// An EXIF block (TIFF structure, as the WebP `EXIF` chunk holds it) written by ImageIO: the source's EXIF, TIFF and
/// GPS dictionaries, orientation 1, are attached to a blank greyscale JPEG of the output size, whose APP1 segment is
/// then cut out. The blank image is calloc'd zeros and compresses to almost nothing; its size makes ImageIO write the
/// right pixel dimensions.
enum EXIFBlock {
    static let header: [UInt8] = Array("Exif".utf8) + [0, 0]
    static var carried: [CFString] {
        [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary]
    }

    static func make(_ properties: [CFString: Any], output: PixelSize) -> Data? {
        let upright = OrientationPolicy.upright(properties)
        var attached: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0]
        for key in carried { attached[key] = upright[key] }
        let (width, height) = (output.width, output.height)
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(count: width * height) as CFData),
            let blank = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, blank, attached as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return segment(Array(jpeg as Data))
    }

    /// The payload of the first APP1 `Exif` segment before the image data, without its 6-byte header.
    static func segment(_ jpeg: [UInt8]) -> Data? {
        guard jpeg.starts(with: [0xFF, 0xD8]) else { return nil }
        var offset = 2
        while offset + 4 <= jpeg.count, jpeg[offset] == 0xFF {
            let marker = jpeg[offset + 1]
            if marker == 0xDA || marker == 0xD9 { return nil }
            let length = Int(jpeg[offset + 2]) << 8 | Int(jpeg[offset + 3])
            guard length >= 2, offset + 2 + length <= jpeg.count else { return nil }
            let payload = jpeg[(offset + 4)..<(offset + 2 + length)]
            if marker == 0xE1, payload.starts(with: header) { return Data(payload.dropFirst(header.count)) }
            offset += 2 + length
        }
        return nil
    }
}
