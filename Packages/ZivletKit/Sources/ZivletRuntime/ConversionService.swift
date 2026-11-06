import EngineImage
import EngineMedia
import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import os

/// The one entry point the app uses (P1-33): dropped URLs + target → a batch, observed as `BatchSnapshot`s.
/// Refused items appear in the snapshot as failed rows, so a drop always ends with a finished snapshot.
public actor ConversionService {
    public nonisolated let snapshots: AsyncStream<BatchSnapshot>
    private let feed: AsyncStream<BatchSnapshot>.Continuation
    private let scheduler: JobScheduler
    private let engines: [any Engine]
    private var factory: JobRequestFactory
    private var batches: [BatchID: BatchSnapshot] = [:]
    /// Finished batches with failures: their target and failed sources, for Retry (the newest few).
    private var retryable: [(batch: BatchID, target: FormatID, urls: [URL])] = []
    /// Finished protect batches with failures: their mode and failed sources, for Retry (it reopens the sheet).
    private var protectRetryable: [(batch: BatchID, retry: ProtectRetry)] = []
    /// Callers of `protect` waiting for their batch to finish.
    private var finishWaiters: [BatchID: CheckedContinuation<BatchSnapshot, Never>] = [:]
    static let retryLimit = 20
    private var listener: Task<Void, Never>?
    private let loadMonitor: SystemLoadMonitor?
    private let loadFeed: Task<Void, Never>?
    private let worker: WorkerSelection?

    /// `engines` answer `unavailableTargets`; the scheduler has its own list. `loadMonitor` (kept alive here) narrows
    /// the scheduler's lanes under memory pressure and Low Power.
    public init(
        scheduler: JobScheduler, engines: [any Engine] = [], factory: JobRequestFactory = JobRequestFactory(),
        loadMonitor: SystemLoadMonitor? = nil, worker: WorkerSelection? = nil
    ) {
        (snapshots, feed) = AsyncStream.makeStream(of: BatchSnapshot.self)
        self.worker = worker
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

    /// The production wiring: the image engine in the worker when it is there and sound, else in-process (P2-01,
    /// D-M6-9); the media engine in-process (ffmpeg is already its own process, D-M6-5); standard lanes, job records
    /// on disk, live system load.
    public static func standard(worker: WorkerSelection = .standard()) -> ConversionService {
        let caches = URL.cachesDirectory.appending(
            path: "app.zivlet.Zivlet/Capabilities", directoryHint: .isDirectory)
        let engines: [any Engine] = [
            WorkerRoutedEngine(local: ImageEngine(), selection: worker), MediaEngine(capabilityCache: caches),
            WorkerOnlyEngine(id: .pdf, pairs: [.protectPDF], selection: worker),
        ]
        return ConversionService(
            scheduler: JobScheduler(engines: engines), engines: engines, loadMonitor: SystemLoadMonitor(),
            worker: worker)
    }

    /// Where conversions run, for Diagnostics.
    public func workerStatus() async -> WorkerStatus {
        guard let worker else { return .inProcess(reason: "no worker in this build") }
        return await worker.status
    }

    /// The `drop→admit` signpost covers checking the drop and handing its jobs to the scheduler (10 §8.7).
    @discardableResult
    public func convert(_ urls: [URL], to target: FormatID) async -> BatchID {
        let signposter = JobSignposts.signposter
        let admission = signposter.beginInterval("drop→admit", id: signposter.makeSignpostID())
        listen()
        let batch = BatchID()
        let plan = factory.requests(for: urls, target: target)
        let snapshot = BatchSnapshot(batch: batch, target: target, plan: plan)
        batches[batch] = snapshot
        feed.yield(snapshot)
        await scheduler.submit(plan.requests, as: batch)
        signposter.endInterval("drop→admit", admission)
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

    /// The catalog pairs an engine handles and can run here (plan 20f E11, G-M7-2), so the wheel offers a conversion
    /// only for sources that have one: a PDF shows none until an engine reads PDFs (P2-12).
    public func availablePairs(catalog: ConversionCatalog = .standard) async -> Set<ConversionPair> {
        var available: Set<ConversionPair> = []
        for pair in catalog.pairs {
            guard let engine = engines.first(where: { $0.handles(pair) }) else { continue }
            if await engine.availability(of: pair).isAvailable { available.insert(pair) }
        }
        return available
    }

    /// Every engine's helper versions, in engine order (Settings › Advanced).
    public func helperVersions() async -> [HelperVersion] {
        var versions: [HelperVersion] = []
        for case let reporter as any HelperVersionReporting in engines { versions += await reporter.helperVersions() }
        return versions
    }

    /// Re-submits the failed items of a finished batch to the same target (P1-41); nil when it has none (or is
    /// no longer remembered).
    public func retry(_ batch: BatchID) async -> BatchID? {
        guard let entry = retryable.first(where: { $0.batch == batch }) else { return nil }
        retryable.removeAll { $0.batch == batch }
        return await convert(entry.urls, to: entry.target)
    }

    /// LOCK · UNLOCK's jobs (plan 20f E7): one per PDF with that file's secrets, shown like any batch; returns each
    /// file's final state. The secrets of refused files are wiped at once; the rest as each job ends (D-M7-14).
    public func protect(_ files: [URL], spec: ProtectSpec, secrets: [URL: JobSecrets]) async -> [URL: JobState] {
        listen()
        let batch = BatchID()
        let plan = factory.protectRequests(for: files, spec: spec)
        let held = Self.hold(secrets, for: plan.requests)
        let snapshot = BatchSnapshot(batch: batch, target: .pdf, plan: plan, protect: spec.mode)
        batches[batch] = snapshot
        feed.yield(snapshot)
        let final = await withCheckedContinuation { continuation in
            finishWaiters[batch] = continuation
            Task { await self.submit(plan.requests, as: batch, secrets: held) }
        }
        return Dictionary(
            final.items.compactMap { item in item.source.map { ($0.url, item.state) } },
            uniquingKeysWith: { first, _ in first })
    }

    private func submit(_ requests: [JobRequest], as batch: BatchID, secrets: BatchSecrets) async {
        await scheduler.submit(requests, as: batch, secrets: secrets)
    }

    /// The accepted jobs' secrets; any secret no accepted job holds is wiped now.
    static func hold(_ secrets: [URL: JobSecrets], for requests: [JobRequest]) -> BatchSecrets {
        let held = Dictionary(
            requests.compactMap { request in secrets[request.input.url].map { (request.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        let kept = held.values.flatMap(\.all)
        for secret in secrets.values.flatMap(\.all) where !kept.contains(where: { $0 === secret }) { secret.wipe() }
        return BatchSecrets(held)
    }

    /// A finished protect batch's failed files and mode, for its Retry (which reopens the sheet); nil when it has
    /// none or is no longer remembered.
    public func protectRetry(_ batch: BatchID) -> ProtectRetry? {
        guard let entry = protectRetryable.first(where: { $0.batch == batch }) else { return nil }
        protectRetryable.removeAll { $0.batch == batch }
        return entry.retry
    }

    /// What each dropped PDF is, read in the worker without a password (plan 20f E9). With no worker, each is refused
    /// as the PDF engine missing: a PDF is never read with qpdf in the app (D-M7-16).
    public func inspectPDFs(_ files: [URL]) async -> [PDFInspection] {
        guard let worker, case .worker(let connection, _) = await worker.choice() else {
            return files.map { _ in .refused(.engineMissing(.pdf)) }
        }
        do {
            return try await connection.inspectPDFs(files)
        } catch {
            return files.map { _ in .refused(error) }
        }
    }

    /// Settings changed the folder used when a source folder is read-only (01-prd FR-17); later drops use it.
    public func use(fallbackFolder: URL) {
        factory = factory.with(fallbackFolder: fallbackFolder)
    }

    public func cancel(_ batch: BatchID) async {
        await scheduler.cancel(batch: batch)
    }

    /// Quit: cancel everything and wait at most `limit` (03a §4.2), then end the worker session.
    public func shutdown(within limit: Duration) async -> Bool {
        let stopped = await scheduler.shutdown(within: limit)
        worker?.workerConnection.close()
        return stopped
    }

    private func remember(_ snapshot: BatchSnapshot) {
        let failed = snapshot.items.compactMap { item -> URL? in
            guard case .failed = item.state else { return nil }
            return item.source?.url
        }
        guard !failed.isEmpty else { return }
        if let mode = snapshot.protect {
            let entry = (snapshot.batch, ProtectRetry(files: failed, mode: mode))
            protectRetryable = Array(([entry] + protectRetryable).prefix(Self.retryLimit))
            return
        }
        retryable = Array(([(snapshot.batch, snapshot.target, failed)] + retryable).prefix(Self.retryLimit))
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
        if next.isFinished { remember(next) }
        feed.yield(next)
        if next.isFinished { finishWaiters.removeValue(forKey: batch)?.resume(returning: next) }
    }
}

extension ConversionService: ProtectSubmitting {}

/// A protect batch's Retry: its failed files and the mode they were in.
public struct ProtectRetry: Sendable, Equatable {
    public let files: [URL]
    public let mode: ProtectSpec.Mode

    public init(files: [URL], mode: ProtectSpec.Mode) {
        self.files = files
        self.mode = mode
    }
}

extension JobEvent {
    var batch: BatchID? {
        switch self {
        case .submitted(let batch, _), .changed(let batch, _, _), .noted(let batch, _, _), .finished(let batch): batch
        }
    }
}
