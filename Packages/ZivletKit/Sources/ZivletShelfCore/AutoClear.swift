import Foundation

/// When items leave a box on their own (P2-141, 17e §2.3): never (the default), once they were dragged out or
/// moved, or a day after they were added.
public enum AutoClear: String, Sendable, Codable, CaseIterable {
    case off, afterLeaving, after24Hours
}

/// Which items an auto-clear policy removes now. Pure; the controller runs it and removes the ids.
public enum AutoClearPlan {
    public static let day: TimeInterval = 24 * 3600

    /// `left` holds the items whose drag-out or move finished.
    public static func items(in shelf: Shelf, policy: AutoClear, now: Date, left: Set<UUID>) -> Set<UUID> {
        switch policy {
        case .off:
            return []
        case .afterLeaving:
            return Set(shelf.items.map(\.id)).intersection(left)
        case .after24Hours:
            return Set(shelf.items.filter { now.timeIntervalSince($0.addedAt) > day }.map(\.id))
        }
    }
}
