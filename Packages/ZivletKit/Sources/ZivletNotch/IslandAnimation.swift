import SwiftUI
import ZivletNotchCore

/// How a host animates its shape. The app uses `.motion` (the machine's `IslandMotion` curves); tests use `.instant`
/// (completions on the next main-actor turn) or `.slow(seconds)` where the order of completions matters.
public enum IslandAnimation: Sendable, Equatable {
    case instant
    case slow(Double)
    case motion

    /// The SwiftUI animation for `curve` (nil = no animation), how long until it counts as done, and whether the
    /// shape may change size in view (not under Reduce Motion, D-N5).
    func timing(for curve: IslandMotion.Curve) -> (animation: Animation?, seconds: Double, resizes: Bool) {
        switch self {
        case .instant: return (nil, 0, true)
        case .slow(let seconds): return (.linear(duration: seconds), seconds, true)
        case .motion:
            switch curve {
            case .spring(let response, let damping):
                let settle = Spring(response: response, dampingRatio: damping).settlingDuration
                return (.spring(response: response, dampingFraction: damping), min(settle, Self.maxSettle), true)
            case .fade(let seconds): return (.easeInOut(duration: seconds), seconds, false)
            }
        }
    }

    /// A spring's settling time is open-ended; the frame swap waits at most this long.
    static let maxSettle = 0.6
}
