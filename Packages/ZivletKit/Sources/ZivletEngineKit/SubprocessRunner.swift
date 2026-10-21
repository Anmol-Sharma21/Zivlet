import Darwin
import Foundation
import ZivletCore

public enum Termination: Sendable, Equatable {
    case exited(Int32)
    case signaled(Int32)
}

/// One child process to run. Output caps bound memory for hostile or chatty children.
public struct SubprocessRequest: Sendable, Equatable {
    public static let defaultStdoutLimit = 8 << 20
    public static let defaultStderrTailLimit = 64 << 10

    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    /// Bytes of stdout kept; the rest is still read (and streamed as lines) but dropped.
    public let stdoutLimit: Int
    /// Bytes kept from the end of stderr (10 §8.3: 64 KB tail).
    public let stderrTailLimit: Int
    /// The profile the helper runs under; nil runs it as it is (helpers that read no untrusted file).
    public let sandbox: HelperSandbox?

    public init(
        executable: URL, arguments: [String], environment: [String: String] = ChildEnvironment.fixed(),
        stdoutLimit: Int = defaultStdoutLimit, stderrTailLimit: Int = defaultStderrTailLimit,
        sandbox: HelperSandbox? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.stdoutLimit = max(0, stdoutLimit)
        self.stderrTailLimit = max(0, stderrTailLimit)
        self.sandbox = sandbox
    }

    /// What is actually executed: the helper, or `sandbox-exec -p <profile> <helper> …` under a sandbox.
    var launch: (executable: URL, arguments: [String]) {
        guard let sandbox else { return (executable, arguments) }
        return (HelperSandbox.launcher, ["-p", sandbox.profile(helper: executable), executable.path] + arguments)
    }
}

public struct SubprocessResult: Sendable, Equatable {
    public let termination: Termination
    public let stdout: Data
    public let stdoutTruncated: Bool
    public let stderrTail: String

    public init(termination: Termination, stdout: Data, stdoutTruncated: Bool, stderrTail: String) {
        self.termination = termination
        self.stdout = stdout
        self.stdoutTruncated = stdoutTruncated
        self.stderrTail = stderrTail
    }
}

public enum SubprocessError: Error, Equatable, Sendable {
    case launchFailed(errno: Int32)
    /// Waiting for the child failed (for example ECHILD: someone else reaped it), so its outcome is unknown.
    case waitFailed(errno: Int32)
    case cancelled
}

extension SubprocessError {
    /// Launch errnos that mean the helper is not there or cannot be executed at all.
    static let missingHelperCodes: Set<Int32> = [ENOENT, ENOTDIR, EACCES, ENOEXEC, EBADARCH, EBADEXEC]

    /// Only a helper that is not there or cannot be executed is a missing engine; anything else (too many open files,
    /// no processes left, a lost child) keeps its errno, so the user is not told to reinstall.
    public func jobError(engine: EngineID) -> JobError {
        switch self {
        case .cancelled: .cancelled
        case .launchFailed(let code) where Self.missingHelperCodes.contains(code): .engineMissing(engine)
        case .launchFailed(let code), .waitFailed(let code): .helperFailed(errno: code)
        }
    }
}

/// The child environment (10 §8.9): nothing inherited from the app.
public enum ChildEnvironment {
    public static func fixed(temporaryDirectory: String = NSTemporaryDirectory()) -> [String: String] {
        [
            "PATH": "/usr/bin:/bin", "LC_ALL": "C", "TMPDIR": temporaryDirectory, "AV_LOG_FORCE_NOCOLOR": "1",
            "SVT_LOG": "1",
        ]
    }
}

/// Runs a child process; `SubprocessRunner` in production, fakes in engine tests.
public protocol ProcessRunning: Sendable {
    func run(
        _ request: SubprocessRequest, onSpawn: @escaping @Sendable (Int32) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws(SubprocessError) -> SubprocessResult
}

/// Runs helpers with `posix_spawn` in their own process group (index D-M3-1: swift-subprocess 1.0.2 stops its
/// teardown once the leader exits, leaving SIGINT-ignoring grandchildren alive). Cancelling the calling task sends
/// SIGINT to the group, then SIGKILL after `teardownGrace`; after the leader exits, any member left is SIGKILLed.
public struct SubprocessRunner: ProcessRunning {
    public let teardownGrace: Duration

    public init(teardownGrace: Duration = .seconds(1)) { self.teardownGrace = teardownGrace }

    public func run(
        _ request: SubprocessRequest, onSpawn: @escaping @Sendable (Int32) -> Void = { _ in },
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws(SubprocessError) -> SubprocessResult {
        if Task.isCancelled { throw .cancelled }  // a cancelled job never starts a helper
        let launched = try Spawner.launch(request)
        onSpawn(launched.child.pid)
        let grace = teardownGrace
        let result = await withTaskCancellationHandler {
            async let out = PipeReader.collect(launched.stdout, limit: request.stdoutLimit, onLine: onLine)
            async let err = PipeReader.tail(launched.stderr, limit: request.stderrTailLimit)
            let termination = await launched.child.waitForExit()
            let (stdout, truncated) = await out
            let tail = await err
            return termination.map {
                SubprocessResult(termination: $0, stdout: stdout, stdoutTruncated: truncated, stderrTail: tail)
            }
        } onCancel: {
            launched.child.terminate(grace: grace)
        }
        if Task.isCancelled { throw .cancelled }
        return try result.get()
    }
}
