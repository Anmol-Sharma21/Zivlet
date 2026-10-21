import Darwin
import Foundation

/// The profile a helper that parses untrusted media runs under (the M4 review; D-M4-19). Deny by default; the
/// system's base rules (`system.sb`: libraries, frameworks, devices); read the helper's own folder, the job's
/// `reads` (literal files) and stat anything; read and write only inside `writes` (the job's private staging
/// folder); Mach and IOKit for VideoToolbox; no network. The helper is started through `/usr/bin/sandbox-exec`,
/// which applies the profile and then executes the helper in the same process (same PID and process group).
public struct HelperSandbox: Sendable, Equatable {
    public static let launcher = URL(filePath: "/usr/bin/sandbox-exec")
    /// Homebrew keeps a helper's libraries outside its own folder (development only, D-M3-19).
    static let homebrew = "/opt/homebrew"

    public let reads: [URL]
    public let writes: [URL]

    public init(reads: [URL], writes: [URL] = []) {
        self.reads = reads
        self.writes = writes
    }

    public func profile(helper: URL) -> String {
        let executable = Self.real(helper)
        let rules =
            [
                "(version 1)", "(deny default)", #"(import "system.sb")"#,
                "(allow process-exec (literal \(Self.quoted(executable))))",
            ] + Self.helperRoots(executable).map { "(allow file-read* (subpath \(Self.quoted($0))))" }
            + reads.map { "(allow file-read* (literal \(Self.quoted(Self.real($0)))))" }
            + writes.map { "(allow file-read* file-write* (subpath \(Self.quoted(Self.real($0)))))" }
            + [
                "(allow file-read-metadata)", "(allow mach-lookup)", "(allow iokit-open)", "(allow sysctl-read)",
                "(allow ipc-posix-shm)", "(deny network*)",
            ]
        return rules.joined(separator: "\n") + "\n"
    }

    /// The helper's bundle or stage folder (`…/Contents`, `…/media-stage`) when it is deep enough to be one,
    /// else the helper's own folder; plus Homebrew's prefix for a Homebrew helper.
    static func helperRoots(_ executable: String) -> [String] {
        let folder = (executable as NSString).deletingLastPathComponent
        let parent = (folder as NSString).deletingLastPathComponent
        let root = (parent as NSString).pathComponents.count >= 3 ? parent : folder
        return [root] + (executable.hasPrefix(homebrew + "/") ? [homebrew] : [])
    }

    /// The path the kernel checks: symlinks resolved (`/var` → `/private/var`); the path as given when it does not
    /// exist yet.
    static func real(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// An SBPL string literal: backslashes and double quotes escaped.
    static func quoted(_ path: String) -> String {
        "\"" + path.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"") + "\""
    }
}
