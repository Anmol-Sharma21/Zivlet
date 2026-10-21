/// The island's animation curves as plain values (D-N5, spike S6 and S7); the shell maps them to SwiftUI. Under
/// Reduce Motion the island only fades: no spring, no change of size in view.
public struct IslandMotion: Sendable, Equatable {
    public enum Curve: Sendable, Equatable {
        case spring(response: Double, damping: Double)
        case fade(seconds: Double)
    }

    public static let reducedFade = 0.18

    public let expand: Curve
    public let collapse: Curve

    public init(reduceMotion: Bool) {
        if reduceMotion {
            expand = .fade(seconds: Self.reducedFade)
            collapse = .fade(seconds: Self.reducedFade)
        } else {
            expand = .spring(response: 0.38, damping: 0.78)
            collapse = .spring(response: 0.32, damping: 0.9)
        }
    }
}
