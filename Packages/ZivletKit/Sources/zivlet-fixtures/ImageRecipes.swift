import CoreGraphics
import Foundation
import ImageIO

/// One image fixture: its file name and how to make it in a set.
struct ImageRecipe: Sendable {
    let name: String
    let make: @Sendable (FixtureSet, URL) throws(FixtureError) -> Void
}

/// The image fixtures of 05 P1-60 (11 §14 item 3): sRGB stills in every readable raster format, deep P3, alpha,
/// animation, pages, CMYK and the eight EXIF orientations. Drawn by Zivlet; no third-party pictures.
enum ImageRecipes {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? srgb
    static let cmyk = CGColorSpace(name: CGColorSpace.genericCMYK) ?? CGColorSpaceCreateDeviceCMYK()
    static let animationFrames = 4
    static let sequenceFrames = 3
    static let pageCount = 3
    static let frameDelay = 0.1
    /// ImageIO's HEVC sequence encoder is not byte-stable from run to run on this hardware, so the generator checks
    /// that the file decodes instead of hashing it.
    static let unhashed: Set<String> = ["animated.heics"]

    static let all: [ImageRecipe] =
        stills + [
            ImageRecipe(name: "srgb.webp") { set, url throws(FixtureError) in
                try WebPFixture.write(try Canvas.draw(Paint(set.still, space: srgb)), to: url)
            },
            still("p3-16bit.png", type: "public.png") { Paint($0.still, space: displayP3, bits: 16) },
            still("p3-16bit.tiff", type: "public.tiff") { Paint($0.still, space: displayP3, bits: 16) },
            still("alpha.png", type: "public.png") { Paint($0.still, space: srgb, halfTransparent: true) },
            still("alpha.heic", type: "public.heic") { Paint($0.still, space: srgb, halfTransparent: true) },
            still("cmyk.jpg", type: "public.jpeg") { Paint($0.still, space: cmyk) },
            animated("animated.png", type: "public.png", frames: animationFrames, family: .png),
            animated("animated.heics", type: "public.heics", frames: sequenceFrames, family: .heics),
            ImageRecipe(name: "pages.tiff") { set, url throws(FixtureError) in
                let pages = try (0..<pageCount).map { page throws(FixtureError) in
                    try Canvas.draw(Paint(set.still, space: srgb, phase: page))
                }
                try ImageFile.write(pages, type: "public.tiff", to: url)
            },
        ] + orientations

    /// sRGB stills; the JPEG and HEIC are photo-sized in the full set (the bench converts a 12 MP HEIC).
    private static let stills: [ImageRecipe] = [
        still("srgb.jpg", type: "public.jpeg") { Paint($0.photo, space: srgb) },
        still("srgb.png", type: "public.png") { Paint($0.still, space: srgb) },
        still("srgb.heic", type: "public.heic") { Paint($0.photo, space: srgb) },
        still("srgb.tiff", type: "public.tiff") { Paint($0.still, space: srgb) },
        still("srgb.avif", type: "public.avif") { Paint($0.still, space: srgb) },
        still("srgb.bmp", type: "com.microsoft.bmp") { Paint($0.still, space: srgb) },
    ]

    /// JPEGs tagged with each EXIF orientation 1…8 over the same pixels.
    private static let orientations: [ImageRecipe] = (1...8).map { orientation in
        ImageRecipe(name: "orientation-\(orientation).jpg") { set, url throws(FixtureError) in
            let image = try Canvas.draw(Paint(set.still, space: srgb))
            let properties = [kCGImagePropertyOrientation: orientation] as [CFString: Any]
            try ImageFile.write([image], type: "public.jpeg", to: url, frame: properties)
        }
    }

    private static func still(
        _ name: String, type: String, paint: @escaping @Sendable (FixtureSet) -> Paint
    ) -> ImageRecipe {
        ImageRecipe(name: name) { set, url throws(FixtureError) in
            try ImageFile.write([try Canvas.draw(paint(set))], type: type, to: url)
        }
    }

    private static func animated(
        _ name: String, type: String, frames: Int, family: ImageFile.Family
    ) -> ImageRecipe {
        ImageRecipe(name: name) { set, url throws(FixtureError) in
            let images = try (0..<frames).map { frame throws(FixtureError) in
                try Canvas.draw(Paint(set.animation, space: srgb, phase: frame))
            }
            try ImageFile.write(
                images, type: type, to: url, file: family.loopForever, frame: family.delay(frameDelay))
        }
    }
}

/// ImageIO writing with fixed properties only (no dates), so the bytes depend on the pixels and the OS encoders.
enum ImageFile {
    enum Family {
        case png, heics

        var loopForever: [CFString: Any] {
            switch self {
            case .png: [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 0]]
            case .heics: [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSLoopCount: 0]]
            }
        }

        func delay(_ seconds: Double) -> [CFString: Any] {
            switch self {
            case .png: [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: seconds]]
            case .heics: [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSDelayTime: seconds]]
            }
        }
    }

    static func write(
        _ images: [CGImage], type: String, to url: URL, file: [CFString: Any] = [:], frame: [CFString: Any] = [:]
    ) throws(FixtureError) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, images.count, nil)
        else { throw .writing(url.lastPathComponent) }
        if !file.isEmpty { CGImageDestinationSetProperties(destination, file as CFDictionary) }
        for image in images { CGImageDestinationAddImage(destination, image, frame as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { throw .writing(url.lastPathComponent) }
    }
}
