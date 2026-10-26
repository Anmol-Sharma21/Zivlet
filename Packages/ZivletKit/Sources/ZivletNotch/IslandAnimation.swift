import SwiftUI
import ZivletNotchCore

/// How a host animates its shape. The app uses `.motion` (the machine's `IslandMotion` curves); tests use `.instant`
/// (completions on the next main-actor turn) or `.slow(seconds)` where the order of completions matters.
public enum IslandAnimation: Sendable, Equatable {
    case instant
    case slow(Double)
    case motion

    /// The SwiftUI animation (nil = none), how long until it counts as done, and whether the shape may change size
    /// in view (not under Reduce Motion, D-N5).
    typealias Timing = (animation: Animation?, seconds: Double, resizes: Bool)

    func timing(for curve: IslandMotion.Curve) -> Timing {
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

    /// How long a panel's exit fade lasts: the island's collapse settle (at most 0.6 s), or Reduce Motion's short
    /// fade, so the Drop Box leaves in the island's motion language (19c D-BL12).
    public static func exitSeconds(reduceMotion: Bool) -> Double {
        motion.timing(for: IslandMotion(reduceMotion: reduceMotion).collapse).seconds
    }

    /// How new content enters (19b D-NL13): it grows from 0.96 at the top edge while it fades in, inside the shape's
    /// spring, and leaves with opacity only. Under Reduce Motion it only fades.
    func contentTransition(reduceMotion: Bool) -> IslandContentTransition {
        reduceMotion ? .fade : .scaleAndFade(from: IslandContentTransition.enteringScale)
    }
}

/// The content's transition as a plain value; the chrome maps it to SwiftUI.
enum IslandContentTransition: Sendable, Equatable {
    static let enteringScale = 0.96

    case fade
    case scaleAndFade(from: Double)

    var transition: AnyTransition {
        switch self {
        case .fade:
            .opacity
        case .scaleAndFade(let scale):
            .asymmetric(insertion: .opacity.combined(with: .scale(scale: scale, anchor: .top)), removal: .opacity)
        }
    }
}
