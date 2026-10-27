import ZivletCore
import ZivletIPC

/// One session with the worker (D-M6-2). `send` returns the reply to one request; it throws `.workerCrashed` when the
/// session ends before the reply arrives (the worker crashed, was killed or exited), and every later `send` on a
/// closed channel throws the same at once.
public protocol WorkerChannel: Sendable {
    func send(_ request: WorkerRequest) async throws(JobError) -> WorkerReply
    /// The app is done with the session (quit, or the connection dropped it).
    func close()
}

/// Opens worker sessions: XPC in the app (`XPCSessionFactory`), a loopback in tests. `onEvent` receives the worker's
/// events in arrival order, which is not ordered against replies (an event can come after its step's reply);
/// `onClosed` runs once when the worker side ends the session.
public protocol WorkerTransport: Sendable {
    func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
}
