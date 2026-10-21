import Darwin
import Foundation
import Synchronization

/// A spawned child and the read ends of its stdout and stderr pipes.
struct LaunchedChild: Sendable {
    let child: ChildProcess
    let stdout: Int32
    let stderr: Int32
}

/// `posix_spawn` with a new process group, default signal handlers, an empty mask, `/dev/null` stdin and no other
/// inherited descriptors (`POSIX_SPAWN_CLOEXEC_DEFAULT`).
enum Spawner {
    static let resetSignals = [SIGINT, SIGTERM, SIGPIPE, SIGHUP, SIGQUIT, SIGCHLD]

    static func launch(_ request: SubprocessRequest) throws(SubprocessError) -> LaunchedChild {
        let out = try makePipe()
        let err = try makePipe()
        let launched = spawn(request, stdout: out.write, stderr: err.write)
        close(out.write)
        close(err.write)
        switch launched {
        case .success(let pid):
            return LaunchedChild(child: ChildProcess(pid: pid), stdout: out.read, stderr: err.read)
        case .failure(let error):
            close(out.read)
            close(err.read)
            throw error
        }
    }

    private static func makePipe() throws(SubprocessError) -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw .launchFailed(errno: errno) }
        return (fds[0], fds[1])
    }

    private static func spawn(_ request: SubprocessRequest, stdout: Int32, stderr: Int32)
        -> Result<pid_t, SubprocessError>
    {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr, 2)
        configure(&attributes)
        let path = request.executable.path
        let argv = [path] + request.arguments
        let envp = request.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let status = withCStrings(argv) { cArgv in
            withCStrings(envp) { cEnvp in posix_spawn(&pid, path, &actions, &attributes, cArgv, cEnvp) }
        }
        return status == 0 ? .success(pid) : .failure(.launchFailed(errno: status))
    }

    private static func configure(_ attributes: inout posix_spawnattr_t?) {
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in resetSignals { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_set_qos_class_np(&attributes, QOS_CLASS_USER_INITIATED)
    }

    /// A NULL-terminated C string array valid for the duration of `body`.
    private static func withCStrings<R>(
        _ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R
    ) -> R {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress.unsafelyUnwrapped)
        }
    }
}

/// Blocking calls on a thread of their own. A child holds three for its whole life (two pipe reads and the exit
/// wait), so they must not come from the global dispatch queues: their pool is capped at a few dozen threads, and
/// with many children running, a cancelled child's teardown would wait for unrelated children to finish.
enum BlockingThread {
    static func run<T: Sendable>(_ name: String, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread { continuation.resume(returning: body()) }
            thread.name = name
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }
}

/// The child's lifetime. `reaped` is set, under the lock, before the zombie is collected, so a delayed SIGKILL can
/// never hit a recycled PID.
final class ChildProcess: Sendable {
    /// A serial queue is served from the overcommit pool, so the SIGKILL timer fires on time even when the global
    /// queues are saturated.
    static let teardownQueue = DispatchQueue(label: "app.zivlet.subprocess.teardown", qos: .userInitiated)

    let pid: pid_t
    private let reaped = Mutex(false)

    init(pid: pid_t) { self.pid = pid }

    /// SIGINT to the group now, SIGKILL after `grace` unless the child is gone.
    func terminate(grace: Duration) {
        signalGroup(SIGINT)
        let deadline =
            DispatchTime.now() + .nanoseconds(Int(grace.components.seconds * 1_000_000_000))
            + .nanoseconds(Int(grace.components.attoseconds / 1_000_000_000))
        Self.teardownQueue.asyncAfter(deadline: deadline) { [self] in signalGroup(SIGKILL) }
    }

    private func signalGroup(_ signal: Int32) {
        reaped.withLock { isReaped in
            if !isReaped { killpg(pid, signal) }
        }
    }

    /// Waits on its own thread: leader exit (not yet reaped), SIGKILL to any member left, then reap.
    func waitForExit() async -> Result<Termination, SubprocessError> {
        await BlockingThread.run("zivlet.wait.\(pid)") { [self] in blockUntilExit() }
    }

    /// A failed wait (other than EINTR) means the child is no longer ours, so its PID may already be recycled: no
    /// signal is sent and the outcome is reported as unknown, never as a status.
    private func blockUntilExit() -> Result<Termination, SubprocessError> {
        var info = siginfo_t()
        if let code = Self.retryingEINTR({ waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) }) {
            reaped.withLock { $0 = true }
            return .failure(.waitFailed(errno: code))
        }
        reaped.withLock { isReaped in
            killpg(pid, SIGKILL)
            isReaped = true
        }
        var status: Int32 = 0
        if let code = Self.retryingEINTR({ waitpid(pid, &status, 0) }) { return .failure(.waitFailed(errno: code)) }
        let signal = status & 0x7f
        return .success(signal == 0 ? .exited((status >> 8) & 0xff) : .signaled(signal))
    }

    /// Runs `call` until it is not interrupted; the errno of a failure, nil on success.
    private static func retryingEINTR(_ call: () -> Int32) -> Int32? {
        while true {
            if call() != -1 { return nil }
            if errno != EINTR { return errno }
        }
    }
}

/// Blocking pipe reads on their own threads, never on the cooperative pool or the global dispatch queues.
enum PipeReader {
    static let chunkSize = 16_384
    /// A stdout line longer than this is cut (hostile output without newlines).
    static let maxLineBytes = 64 << 10

    static func collect(_ fd: Int32, limit: Int, onLine: @escaping @Sendable (String) -> Void) async -> (Data, Bool) {
        await BlockingThread.run("zivlet.stdout") {
            var kept = Data()
            var truncated = false
            var lines = LineSplitter(maxBytes: maxLineBytes, emit: onLine)
            readAll(fd) { chunk in
                lines.consume(chunk)
                let room = max(0, limit - kept.count)
                kept.append(contentsOf: chunk.prefix(room))
                if chunk.count > room { truncated = true }
            }
            lines.finish()
            return (kept, truncated)
        }
    }

    static func tail(_ fd: Int32, limit: Int) async -> String {
        await BlockingThread.run("zivlet.stderr") {
            var kept = Data()
            readAll(fd) { chunk in
                kept.append(contentsOf: chunk)
                if kept.count > 2 * max(limit, chunkSize) { kept = Data(kept.suffix(limit)) }
            }
            return String(decoding: kept.suffix(limit), as: UTF8.self)
        }
    }

    /// Reads until EOF or an error, then closes `fd`.
    private static func readAll(_ fd: Int32, _ body: (ArraySlice<UInt8>) -> Void) {
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let count = read(fd, &buffer, chunkSize)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            body(buffer[0..<count])
        }
        close(fd)
    }
}

/// Splits a byte stream at "\n" and emits each line (a final unterminated line too).
struct LineSplitter {
    let maxBytes: Int
    let emit: (String) -> Void
    private var pending: [UInt8] = []

    init(maxBytes: Int, emit: @escaping (String) -> Void) {
        self.maxBytes = maxBytes
        self.emit = emit
    }

    mutating func consume(_ chunk: ArraySlice<UInt8>) {
        for byte in chunk {
            if byte == UInt8(ascii: "\n") {
                emit(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
            } else if pending.count < maxBytes {
                pending.append(byte)
            }
        }
    }

    mutating func finish() {
        if !pending.isEmpty { emit(String(decoding: pending, as: UTF8.self)) }
        pending = []
    }
}
