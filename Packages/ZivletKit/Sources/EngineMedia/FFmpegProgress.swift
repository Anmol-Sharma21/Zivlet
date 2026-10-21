import Foundation

/// One `-progress` block: output time so far, encode speed, bytes written, and whether ffmpeg finished.
public struct FFmpegProgressEvent: Sendable, Equatable {
    public let outTimeMicros: Int64?
    public let speed: Double?
    public let isEnd: Bool
    public let totalSize: Int64?

    public init(outTimeMicros: Int64?, speed: Double?, isEnd: Bool, totalSize: Int64? = nil) {
        self.outTimeMicros = outTimeMicros
        self.speed = speed
        self.isEnd = isEnd
        self.totalSize = totalSize
    }
}

/// Pure, immutable parser for `-progress pipe:1` (P1-07, 11 §8.3): feed one `key=value` line, get the next parser and,
/// on each `progress=` line, an event. Only the keys it uses are kept, so foreign output cannot grow it.
public struct FFmpegProgressParser: Sendable, Equatable {
    static let keptKeys: Set<String> = ["out_time_us", "speed", "total_size"]
    /// Below this speed ffmpeg is stalled or warming up, and an estimate would be noise.
    static let minimumSpeedForETA = 0.01
    /// The first two seconds of output give too little to estimate from.
    static let minimumOutputForETA: Int64 = 2_000_000

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
            speed: pending["speed"].flatMap { Double($0.dropLast()) }, isEnd: value == "end",
            totalSize: pending["total_size"].flatMap { Int64($0) }.flatMap { $0 >= 0 ? $0 : nil })
        return (FFmpegProgressParser(), event)
    }

    /// `out_time / expected`, clamped; 1 at the end; `nil` (indeterminate) without a usable duration.
    public static func fraction(_ event: FFmpegProgressEvent, expectedMicros: Int64?) -> Double? {
        if event.isEnd { return 1 }
        guard let expectedMicros, expectedMicros > 0, let out = event.outTimeMicros else { return nil }
        return min(1, Double(out) / Double(expectedMicros))
    }

    /// `(expected − out_time) / speed` (03a §4.5) once two seconds of output exist and the speed is meaningful.
    public static func eta(_ event: FFmpegProgressEvent, expectedMicros: Int64?) -> Duration? {
        guard !event.isEnd, let expectedMicros, expectedMicros > 0, let out = event.outTimeMicros,
            out >= minimumOutputForETA, let speed = event.speed, speed > minimumSpeedForETA
        else { return nil }
        let remaining = Double(max(0, expectedMicros - out)) / speed
        return .microseconds(Int64(remaining.rounded()))
    }
}
