import Foundation
import Testing
import ZivletCore

@testable import EngineMedia

/// Opt-in smoke environment: `ZIVLET_FFMPEG_DIR` names a directory holding `ffmpeg` and `ffprobe`
/// (the vendored build once it exists; any local build until then). Unset → the smoke suite is disabled.
enum SmokeEnvironment {
    static let variable = "ZIVLET_FFMPEG_DIR"

    static var toolDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment[variable], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// One smoke case: how to synthesize a tiny input, the probe the planner sees, and what the output must contain.
struct SmokeCase: Sendable, CustomTestStringConvertible {
    let name: String
    /// ffmpeg input/encode args that write the source; `{dir}` is replaced by the case directory.
    let synth: [String]
    let source: FormatID
    let target: FormatID
    let info: MediaInfo
    let options: MediaOptions?
    let caps: MediaCapabilities
    /// Output streams as `type:codec`, in order.
    let streams: [String]
    /// Extra probe checks keyed `<type>.<field>`: sample_rate, sample_fmt, channels, height.
    let fields: [String: String]
    /// Encoders or filters both the synthesis and the plan need.
    let requires: [String]

    init(
        _ name: String, synth: [String], _ source: FormatID, _ target: FormatID, _ info: MediaInfo,
        options: MediaOptions? = nil, caps: MediaCapabilities = MediaCapabilities(), streams: [String],
        fields: [String: String] = [:], requires: [String]
    ) {
        self.name = name
        self.synth = synth
        self.source = source
        self.target = target
        self.info = info
        self.options = options
        self.caps = caps
        self.streams = streams
        self.fields = fields
        self.requires = requires
    }

    var testDescription: String { name }
}

struct ToolRun {
    let status: Int32
    let stdout: Data
    let stderr: String
}

/// Runs the ffmpeg tools synchronously. Output stays small: `-loglevel error` and short probes.
struct SmokeTools {
    let directory: URL

    var ffmpeg: URL { directory.appendingPathComponent("ffmpeg") }
    var ffprobe: URL { directory.appendingPathComponent("ffprobe") }

    func run(_ tool: URL, _ arguments: [String]) throws -> ToolRun {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = tool
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ToolRun(
            status: process.terminationStatus, stdout: stdout, stderr: String(decoding: stderr, as: UTF8.self))
    }

    /// Names in the second column of `ffmpeg -encoders` and `ffmpeg -filters`.
    func capabilities() throws -> Set<String> {
        let lists = try ["-encoders", "-filters"].map { try run(ffmpeg, ["-hide_banner", $0]).stdout }
        let lines = lists.flatMap { String(decoding: $0, as: UTF8.self).split(separator: "\n") }
        return Set(
            lines.compactMap { $0.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first }.map(
                String.init))
    }

    func probe(_ file: URL) throws -> [ProbeStream] {
        let fields = "stream=codec_type,codec_name,sample_rate,sample_fmt,channels,height"
        let result = try run(ffprobe, ["-v", "error", "-show_entries", fields, "-of", "json", file.path])
        return try JSONDecoder().decode(ProbeOutput.self, from: result.stdout).streams
    }
}

struct ProbeOutput: Decodable {
    let streams: [ProbeStream]
}

struct ProbeStream: Decodable {
    let codecType: String
    let codecName: String?
    let sampleRate: String?
    let sampleFmt: String?
    let channels: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case codecType = "codec_type", codecName = "codec_name", sampleRate = "sample_rate"
        case sampleFmt = "sample_fmt", channels, height
    }

    var summary: String { "\(codecType):\(codecName ?? "?")" }

    func field(_ name: String) -> String? {
        switch name {
        case "sample_rate": sampleRate
        case "sample_fmt": sampleFmt
        case "channels": channels.map(String.init)
        case "height": height.map(String.init)
        default: nil
        }
    }
}
