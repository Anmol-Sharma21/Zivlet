import Darwin
import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit

/// Records what the runner did to a child's group, with the time of each step, and still sends every signal
/// (D-M7-6): SIGINT and SIGKILL in the order sent, and how the leader ended.
public final class RecordingSignals: ChildSignalling {
    public struct Step: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case signal(Int32)
            /// The leader exited; `signal` is the one that ended it, nil for an exit of its own.
            case leaderExited(signal: Int32?)
        }

        public let kind: Kind
        public let at: ContinuousClock.Instant
    }

    private let recorded = Mutex<[Step]>([])

    public init() {}

    public func signalGroup(_ group: pid_t, _ signal: Int32) {
        recorded.withLock { $0.append(Step(kind: .signal(signal), at: .now)) }
        killpg(group, signal)
    }

    public func leaderExited(_ group: pid_t, signal: Int32?) {
        recorded.withLock { $0.append(Step(kind: .leaderExited(signal: signal), at: .now)) }
    }

    public var steps: [Step] { recorded.withLock { $0 } }

    /// The signals sent, in order.
    public var sent: [Int32] {
        steps.compactMap { if case .signal(let signal) = $0.kind { signal } else { nil } }
    }
}

public enum ProcessGroup {
    /// A SIGKILLed background member stays a zombie until launchd reaps it, and signalling a group of zombies fails
    /// with EPERM rather than ESRCH, so the group counts as gone once ESRCH arrives within `limit`. The limit only
    /// bounds a poll that ends at the first ESRCH; it is not a budget (D-M7-5).
    public static func isGone(_ group: Int32, within limit: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            let result = killpg(group, 0)
            let code = errno
            if result == -1, code == ESRCH { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

/// A 10-minute VP9 encode of a lavfi pattern through `engine`, started at once: `encoding` fires at ffmpeg's first
/// progress past zero (mid-encode), `pid` is ffmpeg's group once it has spawned. For the cancel tests (D-M7-6).
public final class MediaCancelRun: Sendable {
    public let task: Task<StagedOutput, any Error>
    public let encoding = Signal()
    private let spawned = SpawnedPID()

    public init(engine: any Engine, staged: URL) throws {
        let argv = [
            "-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats", "-f", "lavfi",
            "-i", "testsrc2=d=600:s=1280x720:r=30", "-c:v", "libvpx-vp9", "-f", "webm", "file:" + staged.path,
        ]
        let plan = try ExecutionPlan(
            engine: .media, stages: [.ffmpeg(FFmpegStage(argv: argv, expectedDurationMicros: 600_000_000))],
            stageWeights: [1], lanes: [.swVideo], outputFormat: .webm, stagedFile: staged)
        let encoding = self.encoding
        let spawned = self.spawned
        let context = ExecutionContext(
            progress: ProgressSink { if ($0.fraction ?? 0) > 0 { encoding.fire() } },
            spawned: { pid in spawned.value.withLock { $0 = pid } })
        task = Task { try await engine.execute(plan, context: context) }
    }

    public var pid: Int32 { spawned.value.withLock { $0 } }
}

private final class SpawnedPID: Sendable {
    let value = Mutex<Int32>(0)
}
