import Foundation

/// Why a typed time was refused, with Zivlet's own sentence for the field.
nonisolated public enum TimecodeError: Error, Sendable, Equatable {
    case malformed
    /// Later than the media's end, which it carries.
    case pastEnd(Duration)

    public var message: String {
        switch self {
        case .malformed: "Use a time like 1:30 or 0:01:30.5"
        case .pastEnd(let end): "That's after the end (\(Timecode.short(end)))"
        }
    }
}

/// Editable timecodes (P2-30, plan 20b A3, D-M7-11): `ss`, `mm:ss` or `hh:mm:ss`, each with an optional `.f` to
/// `.fff`. A lone seconds field may be any size ("90"); after a higher field, minutes and seconds stay below 60.
/// Negative and malformed times are refused, and so is a time after `limit` (the media's duration).
nonisolated public enum Timecode {
    static let maximumDigits = 6

    public static func parse(_ text: String, limit: Duration? = nil) -> Result<Duration, TimecodeError> {
        guard let duration = duration(of: text.trimmingCharacters(in: .whitespaces)) else {
            return .failure(.malformed)
        }
        if let limit, duration > limit { return .failure(.pastEnd(limit)) }
        return .success(duration)
    }

    /// `01:02:03.250`.
    public static func format(_ duration: Duration) -> String {
        let milliseconds = max(0, milliseconds(of: duration))
        let (seconds, fraction) = milliseconds.quotientAndRemainder(dividingBy: 1000)
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return String(format: "%02lld:%02lld:%02lld.%03lld", hours, minutes, seconds % 60, fraction)
    }

    /// `2:14` or `1:02:03`, whole seconds: the end as the error sentence names it.
    static func short(_ duration: Duration) -> String {
        let seconds = max(0, milliseconds(of: duration)) / 1000
        let (hours, minutes) = (seconds / 3600, seconds / 60 % 60)
        if hours > 0 { return String(format: "%lld:%02lld:%02lld", hours, minutes, seconds % 60) }
        return String(format: "%lld:%02lld", minutes, seconds % 60)
    }

    private static func milliseconds(of duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }

    private static func duration(of text: String) -> Duration? {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(fields.count), let last = fields.last else { return nil }
        let parts = last.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, let fraction = fraction(parts.count == 2 ? parts[1] : nil) else { return nil }
        let wholes = fields.dropLast().map { $0 } + [parts[0]]
        guard let numbers = whole(wholes) else { return nil }
        if numbers.count > 1, numbers.dropFirst().contains(where: { $0 >= 60 }) { return nil }
        let seconds = numbers.reduce(Int64(0)) { $0 * 60 + $1 }
        return .milliseconds(seconds * 1000 + fraction)
    }

    /// Every field: 1…6 ASCII digits.
    private static func whole(_ fields: [String]) -> [Int64]? {
        var numbers: [Int64] = []
        for field in fields {
            guard (1...maximumDigits).contains(field.count), field.allSatisfy(\.isASCIIDigit), let number = Int64(field)
            else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// `.f` … `.fff` as milliseconds; no fraction is 0; an empty or longer one is malformed.
    private static func fraction(_ digits: String?) -> Int64? {
        guard let digits else { return 0 }
        guard (1...3).contains(digits.count), digits.allSatisfy(\.isASCIIDigit), let value = Int64(digits) else {
            return nil
        }
        return value * Int64([100, 10, 1][digits.count - 1])
    }
}

nonisolated extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}

/// A timecode field's state: what was typed, the last valid value and the error under the field. A value.
nonisolated public struct TimecodeEntry: Sendable, Equatable {
    public let text: String
    public let value: Duration
    public let error: TimecodeError?
    public let limit: Duration?

    public init(value: Duration, limit: Duration?) {
        self.init(text: Timecode.format(value), value: value, error: nil, limit: limit)
    }

    private init(text: String, value: Duration, error: TimecodeError?, limit: Duration?) {
        self.text = text
        self.value = value
        self.error = error
        self.limit = limit
    }

    /// The typed text, parsed: a valid time becomes the value; an invalid one keeps the last value and shows why.
    public func edited(_ text: String) -> TimecodeEntry {
        switch Timecode.parse(text, limit: limit) {
        case .success(let value): TimecodeEntry(text: text, value: value, error: nil, limit: limit)
        case .failure(let error): TimecodeEntry(text: text, value: value, error: error, limit: limit)
        }
    }
}
