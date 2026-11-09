import Testing
import ZivletRuntime

/// Runs the tests that pause a fake one at a time. `RenameGate`, `FakeBoxTrash.pauseAt` and `HoldingBookmarks` hold
/// the cooperative-pool thread that called them until the test resumes them, and the test can only resume once a pool
/// thread is free to run it. The pool has one thread per core: on a 3-core hosted CI machine (OWN-CI-1) three such
/// tests paused at once took every thread and the run hung. With one holder at a time the rest of the pool stays free.
struct PoolHolder: TestTrait, TestScoping {
    private static let turn = AsyncSemaphore(width: 1)

    @concurrent func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        try await Self.turn.acquire()
        do {
            try await function()
        } catch {
            await Self.turn.release()
            throw error
        }
        await Self.turn.release()
    }
}

extension Trait where Self == PoolHolder {
    /// The test pauses a fake on a pool thread; see `PoolHolder`.
    static var holdsAPoolThread: Self { Self() }
}
