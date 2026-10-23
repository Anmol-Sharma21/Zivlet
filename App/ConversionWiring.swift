import AppKit
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletUI
import os

/// The conversion side of the drop path (P1-33, P1-40): starts batches, shows each in the presenter its drop chose
/// (today's card near the drop or the notch island, D-M5a-8), records finished outputs for Undo, reveals them in
/// Finder when Settings says so, and logs each batch once.
final class ConversionWiring {
    let conversions: ConversionService
    let hud = ResultHUD()
    let notch: NotchHUD
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
    private let undoHistory: UndoHistory
    private let menu: MenuWiring
    private let revealsResults: () -> Bool
    private let defaultRoute: () -> HUDRoute
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now
    private var routes = BatchRoutes(defaultRoute: .nearDrop)
    private var observer: Task<Void, Never>?

    init(
        conversions: ConversionService, undoHistory: UndoHistory, menu: MenuWiring, notch: NotchHUD,
        revealsResults: @escaping () -> Bool, defaultRoute: @escaping () -> HUDRoute,
        undo: @escaping (BatchID) async -> UndoReply
    ) {
        self.conversions = conversions
        self.undoHistory = undoHistory
        self.menu = menu
        self.notch = notch
        self.revealsResults = revealsResults
        self.defaultRoute = defaultRoute
        for presenter in [hud, notch] as [any HUDPresenter] { wire(presenter, undo: undo) }
    }

    /// Both presenters get the same closures; Retry goes through the routes so the new batch stays where it was.
    private func wire(_ presenter: any HUDPresenter, undo: @escaping (BatchID) async -> UndoReply) {
        presenter.onCancel = { [conversions] batch in Task { await conversions.cancel(batch) } }
        presenter.onReveal = { urls in NSWorkspace.shared.activateFileViewerSelecting(urls) }
        presenter.onOpen = { urls in urls.forEach { NSWorkspace.shared.open($0) } }
        presenter.onCopy = { [logger] urls in
            if case .failed = ClipboardAction().copyItems(urls) { logger.error("Copy from the result card refused") }
        }
        presenter.onUndo = undo
        presenter.onRetry = { [weak self] batch, anchor in self?.retry(batch, anchor: anchor) }
    }

    private func retry(_ batch: BatchID, anchor: CGPoint?) {
        routes = routes.withDefaultRoute(defaultRoute()).retrying(batch, anchor: anchor, at: now).forgetting(batch)
        Task { [conversions] in await conversions.retry(batch) }
    }

    private var now: Duration { origin.duration(to: clock.now) }

    private func presenter(_ route: HUDRoute) -> any HUDPresenter { route == .notch ? notch : hud }

    func start() {
        let snapshots = conversions.snapshots
        observer = Task { [weak self] in
            for await snapshot in snapshots { self?.present(snapshot) }
        }
    }

    /// A drop on a conversion slice: its route is the placement now; the HUD appears near `point` or at the island
    /// of `point`'s display (nil = the main screen).
    func convert(_ urls: [URL], to format: FormatID, near point: CGPoint?) -> Task<BatchID, Never> {
        routes = routes.enqueuing(point: point, at: now, route: defaultRoute())
        return Task { [conversions] in await conversions.convert(urls, to: format) }
    }

    /// What a person would read on the card, so automation can see it: the name is private, the sizes public.
    private static func logCard(_ card: ResultCardModel, logger: Logger) {
        guard let line = card.sizeLine, let split = line.range(of: " · ") else { return }
        let name = String(line[..<split.lowerBound])
        let sizes = String(line[split.upperBound...])
        logger.notice("Result card: \(name, privacy: .private) · \(sizes, privacy: .public)")
    }

    /// The first snapshot of a batch claims its route and prepares that presenter once; later ones look it up.
    private func present(_ snapshot: BatchSnapshot) {
        let claim: BatchRoutes.Claim
        (routes, claim) = routes.withDefaultRoute(defaultRoute()).claiming(snapshot.batch)
        let route = claim.isNew ? claim.route.usable(islandHasDisplay: notch.canShow) : claim.route
        if route != claim.route {
            logger.error("The island has no display: this batch shows near the drop")
            routes = routes.rerouting(snapshot.batch, to: route)
        }
        let shown = presenter(route)
        if claim.isNew { shown.prepare(near: claim.point) }
        shown.show(snapshot)
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
