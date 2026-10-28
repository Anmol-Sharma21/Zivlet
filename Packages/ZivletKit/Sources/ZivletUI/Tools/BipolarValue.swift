import Foundation

/// A position on a bipolar slider (P2-30 "bipolar sliders fill from centre", plan 20b A3, D-M7-11): −1…1 with the
/// neutral setting at 0, so the track fills from the centre toward the value. A value: steps return new ones.
public struct BipolarValue: Sendable, Equatable {
    /// The arrow keys' step and the finer one with ⌥.
    public static let step = 0.05
    public static let fineStep = 0.01
    public static let neutral = BipolarValue(0)

    public let position: Double

    /// Clamped to −1…1; a position that is not a number is the neutral one.
    public init(_ position: Double) {
        self.position = position.isNaN ? 0 : min(max(position, -1), 1)
    }

    public enum Step: Sendable { case up, down, home }

    /// One key press: ↑/→ up, ↓/← down (by `step`, or `fineStep` with ⌥), Home back to neutral.
    public func stepped(_ step: Step, fine: Bool = false) -> BipolarValue {
        let size = fine ? Self.fineStep : Self.step
        switch step {
        case .up: return BipolarValue(((position + size) * 100).rounded() / 100)
        case .down: return BipolarValue(((position - size) * 100).rounded() / 100)
        case .home: return .neutral
        }
    }

    /// The filled part of the track: from the centre to the value.
    public var fill: ClosedRange<Double> { Self.fill(for: position) }

    public static func fill(for position: Double) -> ClosedRange<Double> {
        position < 0 ? position...0 : 0...position
    }
}

/// A tool's own range for a bipolar slider: the lower end at −1, the neutral setting at 0, the upper end at 1, each
/// half linear (a speed of 0.25×…1×…4× puts 1× in the middle).
public struct BipolarRange: Sendable, Equatable {
    public let lower: Double
    public let neutral: Double
    public let upper: Double

    public init(lower: Double, neutral: Double, upper: Double) {
        self.lower = lower
        self.neutral = neutral
        self.upper = upper
    }

    public func value(at position: BipolarValue) -> Double {
        let p = position.position
        return p < 0 ? neutral + p * (neutral - lower) : neutral + p * (upper - neutral)
    }

    /// The position of `value`, clamped to the track.
    public func position(for value: Double) -> BipolarValue {
        if value < neutral { return BipolarValue(neutral == lower ? 0 : (value - neutral) / (neutral - lower)) }
        return BipolarValue(upper == neutral ? 0 : (value - neutral) / (upper - neutral))
    }
}
