import ZivletCore

/// Mirror of the `NSDragOperation` bits so the policy stays pure. The shell converts with `rawValue`.
public struct DragOperations: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let copy = DragOperations(rawValue: 1)
    public static let link = DragOperations(rawValue: 2)
    public static let generic = DragOperations(rawValue: 4)
    public static let `private` = DragOperations(rawValue: 8)
    public static let move = DragOperations(rawValue: 16)
    public static let delete = DragOperations(rawValue: 32)
}

/// 03a §2.5 / 15 C-8: on a slice with a target, return the first of copy, generic, link, move that the source offers,
/// so a modifier still held at release never blocks the drop. Zivlet always applies copy semantics; the returned
/// operation is only what the drag source shows. Hub, outside and empty wheels refuse.
public enum DropNegotiation {
    static let preference: [DragOperations] = [.copy, .generic, .link, .move]

    public static func operation(offered: DragOperations, hit: HitResult, hasTarget: Bool) -> DragOperations {
        guard case .slot = hit, hasTarget else { return [] }
        return preference.first { offered.contains($0) } ?? []
    }
}

/// Highlight tick throttle (03a §2.7): at most one tick per 35 ms; a request older than 150 ms when it reaches the
/// player is dropped instead of played late.
public struct FeedbackGate: Sendable, Equatable {
    public let minimumSpacing: Duration
    public let staleAfter: Duration
    public let lastPlayed: Duration?

    public init(
        minimumSpacing: Duration = .milliseconds(35), staleAfter: Duration = .milliseconds(150),
        lastPlayed: Duration? = nil
    ) {
        self.minimumSpacing = minimumSpacing
        self.staleAfter = staleAfter
        self.lastPlayed = lastPlayed
    }

    public func admit(requestedAt: Duration, now: Duration) -> (admitted: Bool, next: FeedbackGate) {
        if now - requestedAt > staleAfter { return (false, self) }
        if let lastPlayed, now - lastPlayed < minimumSpacing { return (false, self) }
        return (true, FeedbackGate(minimumSpacing: minimumSpacing, staleAfter: staleAfter, lastPlayed: now))
    }
}
