import Foundation

/// One `-progress` block: output time so far, encode speed, and whether ffmpeg finished.
public struct FFmpegProgressEvent: Sendable, Equatable {
    public let outTimeMicros: Int64?
    public let speed: Double?
    public let isEnd: Bool

    public init(outTimeMicros: Int64?, speed: Double?, isEnd: Bool) {
        self.outTimeMicros = outTimeMicros
        self.speed = speed
        self.isEnd = isEnd
    }
}

/// Pure, immutable parser for `-progress pipe:1` (P1-07, 11 §8.3): feed one `key=value` line, get the next parser and,
/// on each `progress=` line, an event. Only the keys it uses are kept, so foreign output cannot grow it.
public struct FFmpegProgressParser: Sendable, Equatable {
    static let keptKeys: Set<String> = ["out_time_us", "speed"]

    let pending: [String: String]

    public init() { pending = [:] }

    private init(pending: [String: String]) { self.pending = pending }

    public func consuming(_ line: String) -> (next: FFmpegProgressParser, event: FFmpegProgressEvent?) {
        guard let equals = line.firstIndex(of: "=") else { return (self, nil) }
        let key = String(line[..<equals])
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard key == "progress" else {
            guard Self.keptKeys.contains(key) else { return (self, nil) }
            return (FFmpegProgressParser(pending: pending.merging([key: value]) { _, new in new }), nil)
        }
        let event = FFmpegProgressEvent(
            outTimeMicros: pending["out_time_us"].flatMap { Int64($0) }.map { max(0, $0) },
            speed: pending["speed"].flatMap { Double($0.dropLast()) }, isEnd: value == "end")
        return (FFmpegProgressParser(), event)
    }

    /// `out_time / expected`, clamped; 1 at the end; `nil` (indeterminate) without a usable duration.
    public static func fraction(_ event: FFmpegProgressEvent, expectedMicros: Int64?) -> Double? {
        if event.isEnd { return 1 }
        guard let expectedMicros, expectedMicros > 0, let out = event.outTimeMicros else { return nil }
        return min(1, Double(out) / Double(expectedMicros))
    }
}
