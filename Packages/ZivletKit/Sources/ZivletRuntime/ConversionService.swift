import EngineImage
import EngineMedia
import Foundation
import ZivletCore
import ZivletEngineKit

/// The one entry point the app uses (P1-33): dropped URLs + target → a batch, observed as `BatchSnapshot`s.
/// Refused items appear in the snapshot as failed rows, so a drop always ends with a finished snapshot.
public actor ConversionService {
    public nonisolated let snapshots: AsyncStream<BatchSnapshot>
    private let feed: AsyncStream<BatchSnapshot>.Continuation
    private let scheduler: JobScheduler
    private let engines: [any Engine]
    private var factory: JobRequestFactory
    private var batches: [BatchID: BatchSnapshot] = [:]
    private var listener: Task<Void, Never>?
    private let loadMonitor: SystemLoadMonitor?
    private let loadFeed: Task<Void, Never>?

    /// `engines` answer `unavailableTargets`; the scheduler has its own list. `loadMonitor` (kept alive here) narrows
    /// the scheduler's lanes under memory pressure and Low Power.
    public init(
        scheduler: JobScheduler, engines: [any Engine] = [], factory: JobRequestFactory = JobRequestFactory(),
        loadMonitor: SystemLoadMonitor? = nil
    ) {
        (snapshots, feed) = AsyncStream.makeStream(of: BatchSnapshot.self)
        self.scheduler = scheduler
        self.engines = engines
        self.factory = factory
        self.loadMonitor = loadMonitor
        loadFeed = loadMonitor.map { monitor in
            Task { [scheduler] in
                for await load in monitor.loads { await scheduler.apply(load) }
            }
        }
    }

    /// The production wiring: media (ffmpeg) and image (ImageIO) engines, standard lanes, job records on disk, live
    /// system load.
    public static func standard() -> ConversionService {
        let caches = URL.cachesDirectory.appending(
            path: "app.zivlet.Zivlet/Capabilities", directoryHint: .isDirectory)
        let engines: [any Engine] = [ImageEngine(), MediaEngine(capabilityCache: caches)]
        return ConversionService(
            scheduler: JobScheduler(engines: engines), engines: engines, loadMonitor: SystemLoadMonitor())
    }

    @discardableResult
    public func convert(_ urls: [URL], to target: FormatID) async -> BatchID {
        listen()
        let batch = BatchID()
        let plan = factory.requests(for: urls, target: target)
        let snapshot = BatchSnapshot(batch: batch, target: target, plan: plan)
        batches[batch] = snapshot
        feed.yield(snapshot)
        await scheduler.submit(plan.requests, as: batch)
        return batch
    }

    /// Catalog targets that no engine can produce from any source on this machine, for the wheel's capability
    /// snapshot (03a §3.5, FR-08): no libvorbis hides OGG, no WebP encoder hides WEBP, document targets stay hidden
    /// until their engines exist.
    public func unavailableTargets(catalog: ConversionCatalog = .standard) async -> Set<FormatID> {
        var available: Set<FormatID> = []
        for pair in catalog.pairs where !available.contains(pair.target) {
            guard let engine = engines.first(where: { $0.handles(pair) }) else { continue }
            if await engine.availability(of: pair).isAvailable { available.insert(pair.target) }
        }
        return catalog.distinctTargets.subtracting(available)
    }

    /// Settings changed the folder used when a source folder is read-only (01-prd FR-17); later drops use it.
    public func use(fallbackFolder: URL) {
        factory = factory.with(fallbackFolder: fallbackFolder)
    }

    public func cancel(_ batch: BatchID) async {
        await scheduler.cancel(batch: batch)
    }

    /// Quit: cancel everything and wait at most `limit` (03a §4.2).
    public func shutdown(within limit: Duration) async -> Bool {
        await scheduler.shutdown(within: limit)
    }

    private func listen() {
        guard listener == nil else { return }
        let events = scheduler.events
        listener = Task {
            for await event in events { self.apply(event) }
        }
    }

    private func apply(_ event: JobEvent) {
        guard let batch = event.batch, let snapshot = batches[batch] else { return }
        let next = snapshot.applying(event)
        guard next != snapshot else { return }
        batches[batch] = next.isFinished ? nil : next
        feed.yield(next)
    }
}

extension JobEvent {
    var batch: BatchID? {
        switch self {
        case .submitted(let batch, _), .changed(let batch, _, _), .noted(let batch, _, _), .finished(let batch): batch
        }
    }
}
