import AppKit
import SwiftUI
import ZivletCore
import ZivletRuntime

/// What one HUD panel renders; the snapshot is replaced on every update of its batch.
@Observable
public final class HUDModel {
    public internal(set) var snapshot: BatchSnapshot?
    public let card = CardState()

    public init() {}
}

/// One batch's panel: non-activating, floating, on every Space; its buttons and hover call back with the batch.
final class HUDPanel {
    struct Callbacks {
        let cancel: (BatchID) -> Void
        let act: (BatchID, ResultCardModel.Button) -> Void
        let hover: (BatchID, Bool) -> Void
    }

    let model = HUDModel()
    private let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: HUDLayout.size), styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: true)
    private var hosting: NSHostingView<ResultHUDView>?
    private var batch: BatchID?

    init(_ callbacks: Callbacks) {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = ResultHUDView(
            model: model,
            cancel: { [weak self] in if let batch = self?.batch { callbacks.cancel(batch) } },
            act: { [weak self] button in if let batch = self?.batch { callbacks.act(batch, button) } },
            hover: { [weak self] inside in if let batch = self?.batch { callbacks.hover(batch, inside) } })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: HUDLayout.size)
        panel.contentView = hosting
        self.hosting = hosting
    }

    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    func bind(_ batch: BatchID) { self.batch = batch }

    func place(_ frame: CGRect) { panel.setFrame(frame, display: false) }

    func orderFront() { panel.orderFrontRegardless() }

    func render(_ snapshot: BatchSnapshot) {
        let wasFinished = model.snapshot?.isFinished ?? false
        model.snapshot = snapshot
        guard snapshot.isFinished, !wasFinished else { return }
        refit()
        if let first = snapshot.outputs.first { loadThumbnail(first.url) }
    }

    func showUndo(_ reply: UndoReply) {
        model.card.undoMessage = reply.message
        model.card.undoCanRetry = reply.canRetry
        refit()
    }

    func showDetails() {
        model.card.showsDetails = true
        refit()
    }

    func close() { panel.orderOut(nil) }

    private func loadThumbnail(_ url: URL) {
        Task { [weak self] in
            let image = await ThumbnailLoader.thumbnail(for: url)
            self?.model.card.thumbnail = image
        }
    }

    /// Grows or shrinks to the content (never below the working size), keeping the top edge.
    private func refit() {
        guard let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let height = max(HUDLayout.size.height, hosting.fittingSize.height)
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: HUDLayout.size.width, height: height), display: true)
    }
}
