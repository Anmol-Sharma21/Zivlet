import EngineImage
import EngineMedia
import Foundation
import ZivletCore
import ZivletEngineKit

/// `zivlet-bench image <abs source> <target> [runs]` and `zivlet-bench media <abs source> <target> <ffmpeg dir>`:
/// one conversion through the real engine (prepare, execute, verify) per run, into a temporary folder, and the
/// median wall time on stdout as `<milliseconds>`. Used by Scripts/bench.sh (P1-63); not shipped or gated.
enum BenchTool {
    static let usage = "zivlet-bench image|media <absolute source> <target> [runs | ffmpeg directory]"
    static let defaultRuns = 5

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run(_ arguments: [String]) async throws -> Double {
        guard arguments.count >= 3, arguments[1].hasPrefix("/"), let target = FormatID(rawValue: arguments[2]),
            let source = FormatRegistry.standard.formatID(fileName: arguments[1])
        else { throw Failure(description: "usage: \(usage)") }
        let url = URL(fileURLWithPath: arguments[1])
        switch arguments[0] {
        case "image":
            let runs = arguments.count > 3 ? Int(arguments[3]) ?? defaultRuns : defaultRuns
            return try await median(runs) { try await convert(url, source, to: target, with: ImageEngine()) }
        case "media":
            guard arguments.count > 3, arguments[3].hasPrefix("/") else { throw Failure(description: usage) }
            // Release builds ignore ZIVLET_FFMPEG_DIR, so the stage is passed as the helper folder; it is not inside an
            // app bundle, so the signature check is the bench's own (the bench measures speed, not trust).
            let locator = EngineLocator(
                bundledHelpers: URL(fileURLWithPath: arguments[3], isDirectory: true), environment: [:],
                developmentDirectories: [])
            let engine = MediaEngine(locator: locator, integrity: StageHelpers())
            return try await median(1) { try await convert(url, source, to: target, with: engine) }
        default:
            throw Failure(description: "usage: \(usage)")
        }
    }

    /// Median of `runs` timings, in milliseconds.
    static func median(_ runs: Int, _ body: () async throws -> Void) async throws -> Double {
        var times: [Double] = []
        for _ in 0..<max(1, runs) {
            let start = ContinuousClock.now
            try await body()
            let elapsed = ContinuousClock.now - start
            times.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        return times.sorted()[times.count / 2]
    }

    static func convert(_ url: URL, _ source: FormatID, to target: FormatID, with engine: any Engine) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "zivlet-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        let input = try InputItem(url: url, format: source, byteCount: size)
        let request = try JobRequest(input: input, operation: .convert(target), destination: folder)
        let workspace = JobWorkspace(job: request.id, stagedFile: folder.appending(path: "staged.\(target.rawValue)"))
        let plan = try await engine.prepare(request, workspace: workspace)
        let output = try await engine.execute(plan, context: ExecutionContext())
        try await engine.verify(output, plan: plan)
    }
}

/// The vendored stage outside an app bundle: present and executable is all the bench needs.
struct StageHelpers: HelperIntegrityChecking {
    func check(_ tools: MediaTools) throws(JobError) {
        guard FileManager.default.isExecutableFile(atPath: tools.ffmpeg.path) else { throw .engineMissing(.media) }
    }
}

do {
    let milliseconds = try await BenchTool.run(Array(CommandLine.arguments.dropFirst()))
    FileHandle.standardOutput.write(Data(String(format: "%.1f\n", milliseconds).utf8))
} catch {
    FileHandle.standardError.write(Data("zivlet-bench: \(error)\n".utf8))
    exit(1)
}
