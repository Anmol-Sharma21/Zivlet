import EngineImage
import EngineMedia
import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletRuntime

/// Facts about a fixture: media (ffprobe) or image (ImageIO).
enum FixtureFacts: Sendable {
    case media(MediaFacts)
    case image(ImageFacts)
}

/// One finished conversion: the published file in its own temporary folder (removed by `discard`).
struct MatrixOutput: Sendable {
    let url: URL
    let folder: URL
    let notes: [PlanNote]

    func discard() { try? FileManager.default.removeItem(at: folder) }
}

/// Shared state of a matrix run: the E1 fixtures, the media tools (the vendored stage unless `ZIVLET_FFMPEG_DIR`
/// names others) and the real engines. Each conversion gets its own `ConversionService`, scheduler and folder, so
/// parallel test cases never read each other's snapshots.
actor MatrixRig {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let stage = repository.appending(path: "Vendor/out/media-stage/Helpers", directoryHint: .isDirectory)
    private static let instance = Task { try MatrixRig() }

    static func shared() async throws -> MatrixRig { try await instance.value }

    nonisolated let fixtures: URL
    nonisolated let tools: MediaTools
    nonisolated let isVendored: Bool
    nonisolated let engines: [any Engine]
    private var facts: [FormatID: FixtureFacts] = [:]

    private init() throws {
        let environment = ProcessInfo.processInfo.environment
        fixtures =
            environment["ZIVLET_FIXTURES_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.repository.appending(path: "build/fixtures/small", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: fixtures.appending(path: "manifest.sha256").path) else {
            throw MatrixFailure("no fixtures in \(fixtures.path): run make fixtures first")
        }
        let directory = environment[EngineLocator.overrideVariable].map { URL(fileURLWithPath: $0) } ?? Self.stage
        tools = MediaTools(directory: directory, origin: .override)
        guard FileManager.default.isExecutableFile(atPath: tools.ffmpeg.path) else {
            throw MatrixFailure("no ffmpeg in \(directory.path): run make vendor or set ZIVLET_FFMPEG_DIR")
        }
        isVendored = directory.standardizedFileURL.path == Self.stage.standardizedFileURL.path
        let locator = EngineLocator(
            bundledHelpers: nil, environment: [EngineLocator.overrideVariable: directory.path],
            developmentDirectories: [])
        engines = [ImageEngine(), MediaEngine(locator: locator)]
    }

    func availability(_ pair: ConversionPair) async -> RouteAvailability {
        guard let engine = engines.first(where: { $0.handles(pair) }) else { return .unavailable(["no engine"]) }
        return await engine.availability(of: pair)
    }

    func fixture(_ source: FormatID) throws -> URL {
        guard let name = MatrixFixtures.primary[source] else { throw MatrixFailure("no fixture for \(source)") }
        return fixtures.appending(path: name)
    }

    func fixtureFacts(_ source: FormatID) async throws -> FixtureFacts {
        if let known = facts[source] { return known }
        let url = try fixture(source)
        let read: FixtureFacts =
            switch FormatRegistry.standard.format(source).category {
            case .svg: .image(.svgDrawing)
            case .raster: .image(try ImageFacts.read(url))
            default: .media(try await MediaFacts.read(url, ffprobe: tools.ffprobe))
            }
        facts[source] = read
        return read
    }

    /// Copies the fixture into a fresh folder and converts it through `ConversionService` (request → probe → plan →
    /// execute → verify → publish).
    nonisolated func convert(_ pair: ConversionPair, fixture: URL) async throws -> MatrixOutput {
        switch try await run(fixture, to: pair.target) {
        case .converted(let output): return output
        case .refused(let error): throw MatrixFailure("\(pair.testDescription) failed: \(error)")
        }
    }

    /// One drop of `input` onto `target`, from a fresh folder. `copying: false` drops the file where it is, for
    /// symlinks and FIFOs that admission must refuse before anything is written.
    nonisolated func run(_ input: URL, to target: FormatID, copying: Bool = true) async throws -> MatrixRun {
        let folder = FileManager.default.temporaryDirectory.appending(path: "zivlet-matrix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dropped = copying ? folder.appending(path: input.lastPathComponent) : input
        if copying { try FileManager.default.copyItem(at: input, to: dropped) }
        let scheduler = JobScheduler(engines: engines, records: nil)
        let service = ConversionService(
            scheduler: scheduler, engines: engines, factory: JobRequestFactory(fallbackFolder: folder))
        let batch = await service.convert([dropped], to: target)
        var last: BatchSnapshot?
        for await snapshot in service.snapshots where snapshot.batch == batch {
            last = snapshot
            if snapshot.isFinished { break }
        }
        if let last, let output = last.outputs.first {
            return .converted(MatrixOutput(url: output.url, folder: folder, notes: last.items.flatMap(\.notes)))
        }
        try? FileManager.default.removeItem(at: folder)
        return .refused(last?.failures.first?.error ?? .internalInvariant("the batch never finished"))
    }
}

/// How one drop ended.
enum MatrixRun: Sendable {
    case converted(MatrixOutput)
    case refused(JobError)
}
