import AppKit
import ZivletCore
import ZivletRuntime
import os

/// What an undo said, and whether pressing Undo again can still help.
public struct UndoReply: Sendable, Equatable {
    public let message: String
    public let canRetry: Bool

    public init(message: String, canRetry: Bool) {
        self.message = message
        self.canRetry = canRetry
    }
}

/// The conversion HUD (01-prd FR-14, P1-40, P1-41): one non-activating glass panel per batch near its drop point,
/// cascading 24 pt for each batch already on screen. Progress and Cancel while working; then the result. A
/// success leaves after a while; a failure stays until closed (`HUDBoard`). Every button acts on its own batch.
public final class ResultHUD {
    public static let successLinger = Duration.seconds(6)

    public var onCancel: (BatchID) -> Void = { _ in }
    public var onReveal: ([URL]) -> Void = { _ in }
    /// Undoes a batch and returns the sentence to show in its place.
    public var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }

    private let screens: () -> [CGRect]
    private let signposter = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "hud")
    private var board = HUDBoard()
    private var panels: [BatchID: HUDPanel] = [:]
    private var order: [BatchID] = []
    private var pending: [(anchor: CGPoint?, interval: OSSignpostIntervalState)] = []
    private var lingers: [BatchID: Task<Void, Never>] = [:]
    /// Built at launch, so the first drop only places and fills a panel (≤ 50 ms, P1-40).
    private var spare: HUDPanel?

    public init(screens: @escaping () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) }) {
        self.screens = screens
        spare = makePanel()
    }

    public var isVisible: Bool { panels.values.contains { $0.isVisible } }

    /// The open panels' frames, oldest first.
    public var panelFrames: [CGRect] { order.compactMap { panels[$0]?.frame } }

    /// A drop happened at `point` (nil = centre of the main screen); the next new batch opens there.
    public func prepare(near point: CGPoint?) {
        pending.append((point, signposter.beginInterval("drop→hud")))
    }

    public func show(_ snapshot: BatchSnapshot) {
        board = board.updating(snapshot)
        let panel = panels[snapshot.batch] ?? open(snapshot.batch)
        panel.render(snapshot)
        lingers[snapshot.batch]?.cancel()
        if snapshot.isFinished, !snapshot.needsAcknowledgementInHUD, panel.model.undoMessage == nil {
            linger(snapshot.batch)
        }
    }

    /// The batch's panel closes; the others stay where they are.
    public func close(_ batch: BatchID) {
        board = board.dismissing(batch)
        lingers.removeValue(forKey: batch)?.cancel()
        panels.removeValue(forKey: batch)?.close()
        order.removeAll { $0 == batch }
    }

    private func open(_ batch: BatchID) -> HUDPanel {
        let drop = pending.isEmpty ? nil : pending.removeFirst()
        let panel = spare ?? makePanel()
        spare = nil
        let screen = HUDLayout.screen(for: drop?.anchor, in: screens()) ?? .zero
        panel.place(HUDLayout.frame(anchor: drop?.anchor, index: panels.count, screen: screen))
        panel.bind(batch)
        panels[batch] = panel
        order.append(batch)
        panel.orderFront()
        if let interval = drop?.interval { signposter.endInterval("drop→hud", interval) }
        return panel
    }

    private func makePanel() -> HUDPanel {
        HUDPanel(
            cancel: { [weak self] batch in self?.onCancel(batch) },
            reveal: { [weak self] batch in self?.reveal(batch) },
            undo: { [weak self] batch in self?.undo(batch) },
            close: { [weak self] batch in self?.close(batch) })
    }

    /// A success leaves after a while, unless it was closed or undone meanwhile.
    private func linger(_ batch: BatchID) {
        lingers[batch] = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.successLinger)
            } catch {
                return  // re-rendered or closed meanwhile
            }
            guard let self else { return }
            self.board = self.board.expiring(batch)
            if !self.board.snapshots.contains(where: { $0.batch == batch }) { self.close(batch) }
        }
    }

    private func reveal(_ batch: BatchID) {
        onReveal(board.snapshots.first { $0.batch == batch }?.outputs.map(\.url) ?? [])
    }

    private func undo(_ batch: BatchID) {
        lingers.removeValue(forKey: batch)?.cancel()
        Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            self?.panels[batch]?.showUndo(reply)
        }
    }
}

extension BatchSnapshot {
    /// Finished with a failure: stays until closed.
    var needsAcknowledgementInHUD: Bool { isFinished && !failures.isEmpty }
}
