import Foundation

/// The app session a request came over (G-M6-21). The worker keeps each step and each early cancel under it, so a
/// session's end, or a cancel it sends, never reaches a retry of the same job on the next session.
public struct WorkerSessionID: Hashable, Sendable {
    /// For a caller that has only one session.
    public static let single = WorkerSessionID()

    private let id = UUID()

    public init() {}
}
