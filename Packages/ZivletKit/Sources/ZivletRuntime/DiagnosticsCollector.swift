import CryptoKit
import Darwin
import Foundation
import OSLog
import ZivletEngineKit

/// Gathers `DiagnosticsSources` on this Mac (P1-48): the app's version, macOS and the Mac model, helper versions with
/// the SHA-256 of ffmpeg and ffprobe, the capability cache, and this process's last log lines from
/// `OSLogStore(scope: .currentProcessIdentifier)`. Settings and the trigger trace come from the app. Local reads only.
/// `collect` is `@concurrent`: the hashing and the log read never run on the caller's actor (the Settings button is
/// on the main actor).
public struct DiagnosticsCollector: Sendable {
    public static let subsystem = "app.zivlet.Zivlet"
    /// How far back the log store is read; the report keeps the last `Diagnostics.logLimit` lines of that.
    static let logWindow: TimeInterval = 10 * 60

    let bundle: Bundle
    let capabilityCache: URL
    let tools: MediaTools?
    /// Called once where the work starts (tests check the thread).
    let observe: @Sendable () -> Void

    public init(
        bundle: Bundle = .main,
        capabilityCache: URL = URL.cachesDirectory.appending(
            path: "app.zivlet.Zivlet/Capabilities", directoryHint: .isDirectory),
        tools: MediaTools? = try? EngineLocator().locateMediaTools(), observe: @escaping @Sendable () -> Void = {}
    ) {
        self.bundle = bundle
        self.capabilityCache = capabilityCache
        self.tools = tools
        self.observe = observe
    }

    @concurrent public func collect(settingsJSON: String, triggerTrace: [String], helpers: [HelperVersion]) async
        -> DiagnosticsSources
    {
        observe()
        let info = bundle.infoDictionary ?? [:]
        return DiagnosticsSources(
            version: info["CFBundleShortVersionString"] as? String ?? "development",
            build: info["CFBundleVersion"] as? String ?? "0",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString, model: Self.model(),
            helpers: helperReports(helpers), capabilities: capabilities(), settings: settingsJSON,
            log: Self.recentLog(limit: Diagnostics.logLimit, since: Self.logStart(now: Date())), trigger: triggerTrace,
            home: FileManager.default.homeDirectoryForCurrentUser.path)
    }

    /// ffmpeg and ffprobe with their hashes; the in-process libraries without one.
    func helperReports(_ helpers: [HelperVersion]) -> [HelperReport] {
        let ffmpegVersion = helpers.first { $0.name == "FFmpeg" }?.version
        let binaries = [tools?.ffmpeg, tools?.ffprobe].compactMap { $0 }.map { url in
            HelperReport(name: url.lastPathComponent, version: ffmpegVersion, sha256: Self.sha256(of: url))
        }
        let linked = helpers.filter { $0.name != "FFmpeg" }.map {
            HelperReport(name: $0.name, version: $0.version, sha256: nil)
        }
        return binaries + linked
    }

    /// Every JSON file of the capability cache, by name.
    func capabilities() -> String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: capabilityCache.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            guard let text = try? String(contentsOf: capabilityCache.appending(path: name), encoding: .utf8) else {
                return nil
            }
            return "\(name): \(text)"
        }.joined(separator: "\n")
    }

    /// SHA-256 of a file, read in 1 MiB chunks; nil when it cannot be read.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `hw.model`, for example "Mac14,12".
    static func model() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func logStart(now: Date) -> Date { now.addingTimeInterval(-logWindow) }

    /// This process's last `limit` lines from Zivlet's subsystem since `start`: "HH:mm:ss.SSS [category] message".
    static func recentLog(limit: Int, since start: Date) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let entries = try store.getEntries(at: store.position(date: start), matching: predicate)
                .compactMap { $0 as? OSLogEntryLog }
            let format = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute().second()
                .secondFraction(.fractional(3))
            return entries.suffix(limit).map { "\($0.date.formatted(format)) [\($0.category)] \($0.composedMessage)" }
        } catch {
            return ["(the log could not be read: \(error.localizedDescription))"]
        }
    }
}
