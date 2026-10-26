/// What a running Move to… or Copy to… tells its caller (the Drop Box's busy overlay, G-M5b-9): the item count once
/// the folder is chosen and the plan made, then each item done. `advanced` is called on the executor's thread.
nonisolated public struct TransferProgress: Sendable {
    public let started: @MainActor @Sendable (_ count: Int) -> Void
    public let advanced: MoveExecutor.Progress

    public init(
        started: @escaping @MainActor @Sendable (_ count: Int) -> Void, advanced: @escaping MoveExecutor.Progress
    ) {
        self.started = started
        self.advanced = advanced
    }

    /// Tells nobody: the wheel's Move to… shows only its result.
    public static let silent = TransferProgress(started: { _ in }, advanced: { _, _ in })
}
