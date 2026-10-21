import Foundation
import ImageIO

/// Frame durations and loop count of an animated source (APNG, HEIC sequence, GIF dictionaries), for the WebP
/// animation. Durations are milliseconds, the source's unclamped delay when it names one; 100 ms when it names none.
struct WebPTiming: Sendable, Equatable {
    static let defaultMillis = 100
    /// Upper bound per frame, so 1,000 frames cannot overflow libwebp's 32-bit timestamps.
    static let maxMillis = 65_535
    static let still = WebPTiming(durations: [defaultMillis], loopCount: 0)

    let durations: [Int]
    /// 0 repeats forever.
    let loopCount: Int

    func duration(at position: Int) -> Int {
        durations.indices.contains(position) ? durations[position] : Self.defaultMillis
    }

    /// (dictionary, unclamped delay, delay, loop count) for each animated family ImageIO reports.
    private static var families: [(CFString, CFString, CFString, CFString)] {
        [
            (
                kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
                kCGImagePropertyAPNGLoopCount
            ),
            (
                kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime,
                kCGImagePropertyHEICSDelayTime,
                kCGImagePropertyHEICSLoopCount
            ),
            (
                kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
                kCGImagePropertyGIFLoopCount
            ),
        ]
    }

    static func read(_ source: CGImageSource, frames: [Int]) -> WebPTiming {
        WebPTiming(durations: frames.map { millis(source, $0) }, loopCount: loopCount(source))
    }

    private static func millis(_ source: CGImageSource, _ index: Int) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        for (dictionary, unclamped, clamped, _) in families {
            guard let family = properties[dictionary] as? [CFString: Any] else { continue }
            let seconds = (family[unclamped] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? family[clamped] as? Double
            guard let seconds, seconds.isFinite, seconds >= 0 else { continue }
            return min(Int((seconds * 1000).rounded()), maxMillis)
        }
        return defaultMillis
    }

    private static func loopCount(_ source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] ?? [:]
        for (dictionary, _, _, loop) in families {
            if let count = (properties[dictionary] as? [CFString: Any])?[loop] as? Int, count >= 0 { return count }
        }
        return 0
    }
}
