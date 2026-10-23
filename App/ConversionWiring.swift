import AppKit
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletUI
import os

/// The conversion side of the drop path (P1-33, P1-40): starts batches, shows them in the result HUD, records
/// finished outputs for Undo, reveals them in Finder when Settings says so, and logs each batch once.
final class ConversionWiring {
    let conversions: ConversionService
    let hud = ResultHUD()
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
    private let undoHistory: UndoHistory
    private let menu: MenuWiring
    private let revealsResults: () -> Bool
    private var observer: Task<Void, Never>?

    init(
        conversions: ConversionService, undoHistory: UndoHistory, menu: MenuWiring,
        revealsResults: @escaping () -> Bool, undo: @escaping (BatchID) async -> UndoReply
    ) {
        self.conversions = conversions
        self.undoHistory = undoHistory
        self.menu = menu
        self.revealsResults = revealsResults
        hud.onCancel = { [conversions] batch in Task { await conversions.cancel(batch) } }
        hud.onReveal = { urls in NSWorkspace.shared.activateFileViewerSelecting(urls) }
        hud.onOpen = { urls in urls.forEach { NSWorkspace.shared.open($0) } }
        hud.onCopy = { [logger] urls in
            if case .failed = ClipboardAction().copyItems(urls) { logger.error("Copy from the result card refused") }
        }
        hud.onUndo = undo
        hud.onRetry = { [hud, conversions] batch, anchor in
            hud.prepare(near: anchor)
            Task { await conversions.retry(batch) }
        }
    }

    func start() {
        let snapshots = conversions.snapshots
        observer = Task { [weak self] in
            for await snapshot in snapshots { self?.present(snapshot) }
        }
    }

    /// A drop on a conversion slice; the HUD appears near `point` (nil = centre of the main screen).
    func convert(_ urls: [URL], to format: FormatID, near point: CGPoint?) -> Task<BatchID, Never> {
        hud.prepare(near: point)
        return Task { [conversions] in await conversions.convert(urls, to: format) }
    }

    /// What a person would read on the card, so automation can see it: the name is private, the sizes public.
    private static func logCard(_ card: ResultCardModel, logger: Logger) {
        guard let line = card.sizeLine, let split = line.range(of: " · ") else { return }
        let name = String(line[..<split.lowerBound])
        let sizes = String(line[split.upperBound...])
        logger.notice("Result card: \(name, privacy: .private) · \(sizes, privacy: .public)")
    }

    private func present(_ snapshot: BatchSnapshot) {
        hud.show(snapshot)
        menu.track(snapshot)
        guard snapshot.isFinished else { return }
        logger.notice("Conversion finished: \(BatchPresentation.logLine(snapshot), privacy: .public)")
        Self.logCard(ResultCardModel(snapshot), logger: logger)
        for failure in snapshot.failures {
            let detail = String(describing: failure.error)  // may hold paths (stderr tail, folder): private
            logger.error(
                "Conversion failed: \(failure.name, privacy: .private): \(failure.error.logDescription, privacy: .public) \(detail, privacy: .private)"
            )
        }
        let published = snapshot.outputs
        if !published.isEmpty {
            Task { [undoHistory, menu] in
                await undoHistory.record(snapshot.batch, outputs: published)
                menu.refreshRecent()
            }
        }
        let outputs = published.map(\.url)
        if !outputs.isEmpty, revealsResults() { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
    }
}
