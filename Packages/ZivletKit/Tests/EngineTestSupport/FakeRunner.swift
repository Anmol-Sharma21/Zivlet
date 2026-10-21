import Foundation
import Synchronization
import ZivletEngineKit

/// A scripted `ProcessRunning`: answers each request from `reply`, streams the reply's stdout as lines, reports a fake
/// PID and records every launch.
public final class FakeRunner: ProcessRunning {
    public typealias Reply = @Sendable (SubprocessRequest) throws(SubprocessError) -> SubprocessResult

    public static let fakePID: Int32 = 4242

    private let reply: Reply
    private let delay: Duration?
    private let launches = Mutex<[SubprocessRequest]>([])

    /// `delay` suspends each launch before it replies, so concurrent callers interleave as with a real child.
    public init(delay: Duration? = nil, reply: @escaping Reply) {
        self.delay = delay
        self.reply = reply
    }

    /// Replies keyed by the request's last argument; anything else exits 1. `failure` makes every launch throw.
    public convenience init(
        replies: [String: SubprocessResult] = [:], failure: SubprocessError? = nil, delay: Duration? = nil
    ) {
        self.init(delay: delay) { request throws(SubprocessError) in
            if let failure { throw failure }
            return replies[request.arguments.last ?? ""] ?? FakeRunner.result("", status: 1)
        }
    }

    public var requests: [SubprocessRequest] { launches.withLock { $0 } }
    public var launchCount: Int { requests.count }

    public func run(
        _ request: SubprocessRequest, onSpawn: @escaping @Sendable (Int32) -> Void,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws(SubprocessError) -> SubprocessResult {
        launches.withLock { $0.append(request) }
        if let delay { try? await Task.sleep(for: delay) }
        let result = try reply(request)
        onSpawn(Self.fakePID)
        String(decoding: result.stdout, as: UTF8.self).split(separator: "\n").forEach { onLine(String($0)) }
        return result
    }

    public static func result(_ stdout: String, status: Int32 = 0, stderr: String = "") -> SubprocessResult {
        SubprocessResult(
            termination: .exited(status), stdout: Data(stdout.utf8), stdoutTruncated: false, stderrTail: stderr)
    }
}
