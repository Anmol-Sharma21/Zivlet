import Foundation

/// One helper in the report: its version and the SHA-256 of the binary (nil for libraries linked into Zivlet).
public struct HelperReport: Sendable, Equatable {
    public let name: String
    public let version: String?
    public let sha256: String?

    public init(name: String, version: String?, sha256: String?) {
        self.name = name
        self.version = version
        self.sha256 = sha256
    }
}

/// Everything Copy Diagnostics puts in its report (P1-48, 10 §8.7), gathered by `DiagnosticsCollector`. Values only.
public struct DiagnosticsSources: Sendable, Equatable {
    public let version: String
    public let build: String
    public let macOS: String
    public let model: String
    public let helpers: [HelperReport]
    /// The capability cache files, as stored.
    public let capabilities: String
    /// The settings as JSON.
    public let settings: String
    public let log: [String]
    public let trigger: [String]
    /// The home folder, so paths under it are shown as `~/…`.
    public let home: String
    /// One line per display (`DisplayGeometry.diagnosticsLine`), the menu-bar display first.
    public let displays: [String]
    /// The notch latch (design/19 §3.2): this Mac has shown a built-in display with a notch.
    public let builtInNotchSeen: Bool
    /// Where conversions run (`WorkerStatus.line`): the worker's pid or the in-process reason, never a path.
    public let worker: String

    public init(
        version: String, build: String, macOS: String, model: String, helpers: [HelperReport], capabilities: String,
        settings: String, log: [String], trigger: [String], home: String, displays: [String] = [],
        builtInNotchSeen: Bool = false, worker: String = WorkerStatus.notStarted.line
    ) {
        self.version = version
        self.build = build
        self.macOS = macOS
        self.model = model
        self.helpers = helpers
        self.capabilities = capabilities
        self.settings = settings
        self.log = log
        self.trigger = trigger
        self.home = home
        self.displays = displays
        self.builtInNotchSeen = builtInNotchSeen
        self.worker = worker
    }

    public func with(log: [String]) -> DiagnosticsSources {
        DiagnosticsSources(
            version: version, build: build, macOS: macOS, model: model, helpers: helpers,
            capabilities: capabilities, settings: settings, log: log, trigger: trigger, home: home,
            displays: displays, builtInNotchSeen: builtInNotchSeen, worker: worker)
    }

    public func with(displays: [String], builtInNotchSeen: Bool) -> DiagnosticsSources {
        DiagnosticsSources(
            version: version, build: build, macOS: macOS, model: model, helpers: helpers,
            capabilities: capabilities, settings: settings, log: log, trigger: trigger, home: home,
            displays: displays, builtInNotchSeen: builtInNotchSeen, worker: worker)
    }

    public func with(worker: String) -> DiagnosticsSources {
        DiagnosticsSources(
            version: version, build: build, macOS: macOS, model: model, helpers: helpers,
            capabilities: capabilities, settings: settings, log: log, trigger: trigger, home: home,
            displays: displays, builtInNotchSeen: builtInNotchSeen, worker: worker)
    }

    /// Fixed sources for tests and previews.
    public static let fake = DiagnosticsSources(
        version: "0.1.0", build: "42", macOS: "Version 26.0 (Build 26A428)", model: "Mac14,12",
        helpers: [
            HelperReport(name: "ffmpeg", version: "9.0.2", sha256: "abc123"),
            HelperReport(name: "libwebp", version: "1.6.0", sha256: nil),
        ],
        capabilities: #"{"encoders":["libx264","libvorbis"]}"#,
        settings: #"{"output":{"fallbackFolder":"\/Users\/fake\/Projects\/Downloads"},"version":1}"#,
        log: [
            "12:00:00.000 [scheduler] Job finished: 1 saved, 0 failed, 0 cancelled",
            "12:00:01.000 [media] opened /Users/fake/Projects/secret.mov",
        ],
        trigger: ["+0.070 s  sample.flagsChanged  live → wheel  [show]"], home: "/Users/fake")
}

public enum DiagnosticsError: Error, Equatable {
    case missing(String)
}

/// The Copy Diagnostics text (P1-48): one `## ` section per source, every path reduced to its last component, the
/// log cut to its last 200 lines. Pure: nothing is read, and nothing is ever sent anywhere.
public enum Diagnostics {
    public static let logLimit = 200

    /// `@concurrent`: the redaction pass runs off the caller's actor.
    @concurrent public static func build(_ sources: DiagnosticsSources) async throws(DiagnosticsError) -> String {
        guard !sources.version.isEmpty else { throw .missing("version") }
        guard !sources.home.isEmpty else { throw .missing("home") }
        let sections = [
            ("Zivlet", "\(sources.version) (\(sources.build))"),
            ("macOS", "\(sources.macOS)\nMac model: \(sources.model)"),
            ("Helpers", sources.helpers.map(helperLine).joined(separator: "\n")),
            ("Worker", sources.worker),
            ("Capabilities", sources.capabilities),
            ("Settings", sources.settings),
            ("Displays", (sources.displays + [notchLine(sources.builtInNotchSeen)]).joined(separator: "\n")),
            ("Recent log", sources.log.suffix(logLimit).joined(separator: "\n")),
            ("Trigger trace", sources.trigger.joined(separator: "\n")),
        ]
        let text = sections.map { "## \($0.0)\n\n\($0.1.isEmpty ? "(none)" : $0.1)\n" }.joined(separator: "\n")
        return DiagnosticsRedaction.redact("# Zivlet diagnostics\n\n" + text, home: sources.home)
    }

    static func notchLine(_ seen: Bool) -> String { "built-in notch seen: \(seen ? "yes" : "no")" }

    static func helperLine(_ helper: HelperReport) -> String {
        let version = helper.version ?? "not found"
        let hash = helper.sha256.map { "SHA-256 \($0)" } ?? "linked into Zivlet"
        return "\(helper.name) \(version), \(hash)"
    }
}
