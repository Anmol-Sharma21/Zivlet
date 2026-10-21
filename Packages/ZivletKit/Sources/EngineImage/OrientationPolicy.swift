import ImageIO

/// Where the EXIF orientation lives in the output (03b §6.1, index D-M3-29). The tag is kept, with the pixels copied
/// unturned, only for types whose readers widely honour it and whose ImageIO encoder writes it: JPEG, HEIC/HEIF and
/// TIFF. Every other type gets the orientation baked into the pixels and written as 1: PNG (its `eXIf` chunk is a
/// late addition many viewers, browsers and editors ignore), BMP and GIF (no orientation field), AVIF (ImageIO's
/// encoder writes no `irot`/`imir`, so the tag would silently be lost), WebP (EXIF chunk with uneven support) and
/// any type not listed, so a new target is safe by default. PDF has no such tag; `PDFPageGeometry` applies the
/// orientation through the page transform. Pure.
enum OrientationPolicy {
    static let tagKeepingTypes: Set<String> = ["public.jpeg", "public.heic", "public.heif", "public.tiff"]
    /// EXIF orientations that change the picture (1 is upright).
    static let turnedOrFlipped = 2...8

    /// True when a frame with this orientation must be decoded upright for this destination type.
    static func bakes(_ orientation: Int, into destinationType: String) -> Bool {
        turnedOrFlipped.contains(orientation) && !tagKeepingTypes.contains(destinationType)
    }

    /// `metadata` for a frame whose pixels are already upright: orientation 1 at the top level and in the TIFF
    /// dictionary (which ImageIO would otherwise write back as the EXIF/XMP orientation).
    static func upright(_ metadata: [CFString: Any]) -> [CFString: Any] {
        var result = metadata
        result[kCGImagePropertyOrientation] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        return result
    }
}
