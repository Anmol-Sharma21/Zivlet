import CryptoKit
import Darwin
import Foundation
import ZivletCore

/// What the located ffmpeg can do (P1-11): encoder and filter names from `-encoders` / `-filters`.
public struct FFmpegCapabilities: Sendable, Codable, Equatable {
    public let encoders: Set<String>
    public let filters: Set<String>

    public init(encoders: Set<String>, filters: Set<String>) {
        self.encoders = encoders
        self.filters = filters
    }

    /// Both lists print a legend, a "------" ruler, then one entry per line: flags, name, description.
    public static func parse(encoderList: String, filterList: String) -> FFmpegCapabilities {
        FFmpegCapabilities(encoders: names(in: encoderList), filters: names(in: filterList))
    }

    static func names(in list: String) -> Set<String> {
        let lines = list.split(separator: "\n")
        guard let ruler = lines.firstIndex(where: isRuler) else { return [] }
        return Set(lines[(ruler + 1)...].compactMap { $0.split(separator: " ").dropFirst().first.map(String.init) })
    }

    private static func isRuler(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" }
    }

    /// Every ffmpeg build lists some encoders and filters; empty sets mean the lists were not read.
    var isPlausible: Bool { !encoders.isEmpty && !filters.isEmpty }

    /// The requested names this build lacks, encoders first, in request order.
    public func missing(encoders wanted: [String], filters wantedFilters: [String] = []) -> [String] {
        wanted.filter { !encoders.contains($0) } + wantedFilters.filter { !filters.contains($0) }
    }
}

/// Runs the capability lists once per ffmpeg binary and OS build (P1-22, 03a §3.5). Results are kept in memory and,
/// when `cacheDirectory` is set, in `<sha256 of the binary>-<os build>.json`, so a later launch spawns nothing.
public actor CapabilityProbe {
    private let tools: MediaTools
    private let runner: any ProcessRunning
    private let cacheDirectory: URL?
    private let osBuild: String
    private let shared = SharedLoad<FFmpegCapabilities>()

    public init(
        tools: MediaTools, runner: any ProcessRunning = SubprocessRunner(), cacheDirectory: URL?,
        osBuild: String = CapabilityProbe.currentOSBuild()
    ) {
        self.tools = tools
        self.runner = runner
        self.cacheDirectory = cacheDirectory
        self.osBuild = osBuild
    }

    /// Concurrent first callers share one probe; a failure is not kept, so a later call probes again.
    public func capabilities() async throws(JobError) -> FFmpegCapabilities {
        try await shared.value { () async throws(JobError) in try await self.load() }
    }

    private func load() async throws(JobError) -> FFmpegCapabilities {
        let file = try cacheFile()
        if let file, let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode(FFmpegCapabilities.self, from: data), decoded.isPlausible
        {
            return decoded
        }
        let probed = FFmpegCapabilities.parse(
            encoderList: try await list("-encoders"), filterList: try await list("-filters"))
        guard probed.isPlausible else {
            throw .processFailed(status: 0, stderrTail: "ffmpeg printed no encoder or filter list.")
        }
        if let file { store(probed, at: file) }
        return probed
    }

    /// The cache file for the current binary, or nil without a cache directory.
    func cacheFile() throws(JobError) -> URL? {
        guard let cacheDirectory else { return nil }
        let binary = tools.ffmpeg.resolvingSymlinksInPath()
        guard let bytes = try? Data(contentsOf: binary, options: .mappedIfSafe) else { throw .engineMissing(.media) }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appending(path: "\(hash)-\(osBuild).json", directoryHint: .notDirectory)
    }

    private func list(_ flag: String) async throws(JobError) -> String {
        let request = SubprocessRequest(executable: tools.ffmpeg, arguments: ["-hide_banner", flag])
        let result: SubprocessResult
        do {
            result = try await runner.run(request, onSpawn: { _ in }, onLine: { _ in })
        } catch {
            throw error.jobError(engine: .media)
        }
        guard result.termination == .exited(0) else {
            throw .processFailed(status: Self.status(result.termination), stderrTail: result.stderrTail)
        }
        guard !result.stdoutTruncated else {
            throw .processFailed(status: 0, stderrTail: "ffmpeg \(flag) printed more than Zivlet reads.")
        }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    /// A cache that cannot be written only costs a re-probe next launch, so the failure is not an error.
    private func store(_ caps: FFmpegCapabilities, at file: URL) {
        guard let data = try? JSONEncoder().encode(caps) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func status(_ termination: Termination) -> Int32 {
        switch termination {
        case .exited(let code): code
        case .signaled(let signal): 128 + signal
        }
    }

    /// `kern.osversion`, for example "26A428".
    public static func currentOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
