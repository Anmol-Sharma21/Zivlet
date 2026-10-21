import AppKit
import SwiftUI
import ZivletCore
import ZivletRuntime

/// What one HUD panel renders; replaced on every snapshot of its batch.
@Observable
public final class HUDModel {
    public internal(set) var snapshot: BatchSnapshot?
    public internal(set) var undoMessage: String?
    /// The last undo left files the Trash refused, so Undo stays available.
    public internal(set) var undoCanRetry = false

    public init() {}
}

/// One batch's panel: non-activating, floating, on every Space; buttons call back with the batch.
final class HUDPanel {
    let model = HUDModel()
    private let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: HUDLayout.size), styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: true)
    private var hosting: NSHostingView<ResultHUDView>?
    private var batch: BatchID?

    init(
        cancel: @escaping (BatchID) -> Void, reveal: @escaping (BatchID) -> Void, undo: @escaping (BatchID) -> Void,
        close: @escaping (BatchID) -> Void
    ) {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let act = { [weak self] (action: @escaping (BatchID) -> Void) in
            { if let batch = self?.batch { action(batch) } }
        }
        let view = ResultHUDView(
            model: model, cancel: act(cancel), reveal: act(reveal), undo: act(undo), close: act(close))
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
        if snapshot.isFinished != wasFinished { refit() }
    }

    func showUndo(_ reply: UndoReply) {
        model.undoMessage = reply.message
        model.undoCanRetry = reply.canRetry
        refit()
    }

    func close() { panel.orderOut(nil) }

    /// Grows or shrinks to the content (never below the working size), keeping the top edge.
    private func refit() {
        guard let hosting else { return }
        let height = max(HUDLayout.size.height, hosting.fittingSize.height)
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: HUDLayout.size.width, height: height), display: true)
    }
}
