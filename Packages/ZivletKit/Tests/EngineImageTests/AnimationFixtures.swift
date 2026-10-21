import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

/// Animated sources made with ImageIO at test time (no committed binaries) and readers for animation facts.
enum AnimationFixture {
    static let palette: [[CGFloat]] = [[1, 0, 0], [0, 0.8, 0], [0, 0, 1], [1, 1, 0]]

    /// A frame filled with one palette colour (cycled by `index`).
    static func frame(_ index: Int, size: PixelSize) throws -> CGImage {
        let space = try #require(ImageFixture.srgb)
        let context = try #require(
            CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let rgb = palette[index % palette.count]
        context.setFillColor(CGColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return try #require(context.makeImage())
    }

    /// An APNG of `frames` frames, each shown for `delay` seconds, repeating `loops` times (0 = forever).
    static func animatedPNG(
        frames: Int, delay: Double, loops: Int = 0, size: PixelSize = ImageFixture.size, in dir: URL
    ) throws -> URL {
        let url = dir.appending(path: "animated.png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, frames, nil))
        let file = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: loops]]
        CGImageDestinationSetProperties(destination, file as CFDictionary)
        let each = [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
        for index in 0..<frames {
            CGImageDestinationAddImage(destination, try frame(index, size: size), each as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination), "could not write the APNG")
        return url
    }

    /// A HEIC image sequence (`public.heics`) of `frames` frames, `delay` seconds each.
    static func heicSequence(frames: Int, delay: Double = 0.1, in dir: URL) throws -> URL {
        let url = dir.appending(path: "sequence.heic")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, "public.heics" as CFString, frames, nil))
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSLoopCount: 0]] as CFDictionary)
        let each = [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSDelayTime: delay]]
        for index in 0..<frames {
            CGImageDestinationAddImage(destination, try frame(index, size: ImageFixture.size), each as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination), "could not write the HEIC sequence")
        return url
    }

    /// Per-frame delays from one ImageIO family dictionary (PNG or HEICS), in seconds rounded to milliseconds.
    static func delays(_ url: URL, family: CFString, key: CFString) throws -> [Double] {
        let image = try source(url)
        return (0..<CGImageSourceGetCount(image)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any] ?? [:]
            let delay = (properties[family] as? [CFString: Any])?[key] as? Double ?? -1
            return (delay * 1000).rounded() / 1000
        }
    }

    static func source(_ url: URL) throws -> CGImageSource {
        try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    static func frameCount(_ url: URL) throws -> Int { CGImageSourceGetCount(try source(url)) }

    /// Per-frame delays of a WebP, in seconds rounded to milliseconds.
    static func webpDelays(_ url: URL) throws -> [Double] {
        let image = try source(url)
        return (0..<CGImageSourceGetCount(image)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any] ?? [:]
            let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] ?? [:]
            let delay = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double ?? webp[kCGImagePropertyWebPDelayTime]
            return ((delay as? Double ?? -1) * 1000).rounded() / 1000
        }
    }

    static func webpLoopCount(_ url: URL) throws -> Int? {
        let properties = CGImageSourceCopyProperties(try source(url), nil) as? [CFString: Any] ?? [:]
        let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] ?? [:]
        return webp[kCGImagePropertyWebPLoopCount] as? Int
    }
}
