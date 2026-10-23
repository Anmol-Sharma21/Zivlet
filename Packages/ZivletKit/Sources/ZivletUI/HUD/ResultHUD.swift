import AppKit
import ZivletCore
import ZivletNotch
import ZivletRuntime
import os

/// What an undo said, whether pressing Undo again can still help, and which outputs it put in the Trash.
public struct UndoReply: Sendable, Equatable {
    public let message: String
    public let canRetry: Bool
    public let removed: [URL]

    public init(message: String, canRetry: Bool, removed: [URL] = []) {
        self.message = message
        self.canRetry = canRetry
        self.removed = removed
    }
}

/// The conversion HUD (01-prd FR-14, P1-40, P1-41): one non-activating glass panel per batch near its drop point,
/// cascading 24 pt for each batch already on screen. Progress and Cancel while working; then the result card. A
/// success leaves after 4 s, held while the pointer is over it; a failure stays until closed (`HUDBoard`). Every
/// button acts on its own batch.
public final class ResultHUD: HUDPresenter {
    public var onCancel: (BatchID) -> Void = { _ in }
    public var onReveal: ([URL]) -> Void = { _ in }
    public var onOpen: ([URL]) -> Void = { _ in }
    public var onCopy: ([URL]) -> Void = { _ in }
    /// Re-submits a batch's failed items: the source batch and the failed card's corner, where the wiring opens the
    /// new batch (D-M5a-8).
    public var onRetry: (BatchID, CGPoint?) -> Void = { _, _ in }
    /// Undoes a batch and returns the sentence to show in its place.
    public var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }

    private let screens: () -> [CGRect]
    private let signposter = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "hud")
    private var board = HUDBoard()
    private var panels: [BatchID: HUDPanel] = [:]
    private var order: [BatchID] = []
    /// Each open panel's cascade index.
    private var slots: [BatchID: Int] = [:]
    private var pending: [(anchor: CGPoint?, interval: OSSignpostIntervalState)] = []
    private var lingers: [BatchID: Task<Void, Never>] = [:]
    private var timers: [BatchID: LingerTimer] = [:]
    private var undos: [BatchID: Task<Void, Never>] = [:]
    private let clock: any MonotonicClock
    /// Built at launch and again after each drop that used it, so a drop only places and fills a panel (≤ 50 ms,
    /// P1-40).
    private var spare: HUDPanel?
    private var refill: Task<Void, Never>?

    public init(
        screens: @escaping () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) },
        clock: any MonotonicClock = SystemClock()
    ) {
        self.screens = screens
        self.clock = clock
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
        guard snapshot.isFinished, timers[snapshot.batch] == nil,
            let duration = ResultCardModel(snapshot).lingers
        else { return }
        timers[snapshot.batch] = LingerTimer(duration: duration).started(at: clock.now())
        scheduleExpiry(snapshot.batch)
    }

    /// The batch's panel closes; the others stay where they are.
    public func close(_ batch: BatchID) {
        board = board.dismissing(batch)
        undos[batch] = nil
        lingers.removeValue(forKey: batch)?.cancel()
        timers[batch] = nil
        panels.removeValue(forKey: batch)?.close()
        slots[batch] = nil
        order.removeAll { $0 == batch }
    }

    var hasSpare: Bool { spare != nil }

    private func open(_ batch: BatchID) -> HUDPanel {
        let drop = pending.isEmpty ? nil : pending.removeFirst()
        let panel = spare ?? makePanel()
        spare = nil
        let screen = HUDLayout.screen(for: drop?.anchor, in: screens()) ?? .zero
        let slot = HUDLayout.freeSlot(used: Set(slots.values))
        panel.place(HUDLayout.frame(anchor: drop?.anchor, index: slot, screen: screen))
        panel.bind(batch)
        panels[batch] = panel
        slots[batch] = slot
        order.append(batch)
        panel.orderFront()
        if let interval = drop?.interval { signposter.endInterval("drop→hud", interval) }
        refillSpare()
        return panel
    }

    /// Builds the next spare on a later main-actor turn, off the drop path.
    private func refillSpare() {
        guard refill == nil else { return }
        refill = Task { [weak self] in
            guard let self else { return }
            if self.spare == nil { self.spare = self.makePanel() }
            self.refill = nil
        }
    }

    private func makePanel() -> HUDPanel {
        HUDPanel(
            HUDPanel.Callbacks(
                cancel: { [weak self] batch in self?.onCancel(batch) },
                act: { [weak self] batch, button in self?.press(button, on: batch) },
                hover: { [weak self] batch, inside in self?.hover(batch, inside: inside) }))
    }

    /// A card button was pressed. Reveal, Open and Copy act only on outputs an undo has not put in the Trash.
    func press(_ button: ResultCardModel.Button, on batch: BatchID) {
        let saved = board.snapshots.first { $0.batch == batch }?.outputs.map(\.url) ?? []
        let outputs = card(batch)?.remaining(saved) ?? saved
        switch button {
        case .undo: undo(batch)
        case .reveal: onReveal(outputs)
        case .open: onOpen(outputs)
        case .copy: onCopy(outputs)
        case .showDetails: panels[batch]?.showDetails()
        case .retry: retry(batch)
        case .close: close(batch)
        }
    }

    /// Hovering holds a lingering card; leaving restarts its full linger.
    private func hover(_ batch: BatchID, inside: Bool) {
        guard let timer = timers[batch] else { return }
        timers[batch] = inside ? timer.hovered(at: clock.now()) : timer.unhovered(at: clock.now())
        scheduleExpiry(batch)
    }

    /// Closes the card when its timer runs out, unless it was hovered, undone or closed meanwhile. The sleep is on
    /// the same clock as `now` (D-N11), so a linger that spans system sleep has passed on wake; a sleep that ends
    /// before the deadline sleeps again.
    private func scheduleExpiry(_ batch: BatchID) {
        lingers.removeValue(forKey: batch)?.cancel()
        guard let deadline = timers[batch]?.deadline else { return }
        let clock = self.clock
        lingers[batch] = Task { [weak self] in
            while clock.now() < deadline {
                do {
                    try await clock.sleep(until: deadline)
                } catch {
                    return  // rescheduled or closed meanwhile
                }
            }
            guard let self, let timer = self.timers[batch], timer.expired(at: clock.now()) else { return }
            self.board = self.board.expiring(batch)
            if !self.board.snapshots.contains(where: { $0.batch == batch }) { self.close(batch) }
        }
    }

    private func retry(_ batch: BatchID) {
        let anchor = panels[batch].map {
            CGPoint(x: $0.frame.minX - HUDLayout.offset, y: $0.frame.maxY + HUDLayout.offset)
        }
        close(batch)
        onRetry(batch, anchor)
    }

    /// Undo once: a press while the reply is pending is ignored. After the reply the success card lingers again.
    private func undo(_ batch: BatchID) {
        guard let card = card(batch), !card.undoInFlight else { return }
        lingers.removeValue(forKey: batch)?.cancel()
        timers[batch] = nil
        card.undoInFlight = true
        undos[batch] = Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            guard let self else { return }
            self.undos[batch] = nil
            guard let panel = self.panels[batch] else { return }
            panel.showUndo(reply)
            self.restartLinger(batch, after: reply)
        }
    }

    private func restartLinger(_ batch: BatchID, after reply: UndoReply) {
        guard !reply.canRetry, let snapshot = board.snapshots.first(where: { $0.batch == batch }),
            let duration = ResultCardModel(snapshot).lingers
        else { return }
        timers[batch] = LingerTimer(duration: duration).started(at: clock.now())
        scheduleExpiry(batch)
    }
}

// Test seams: what the card offers, and whether it is on its way out.
extension ResultHUD {
    func card(_ batch: BatchID) -> CardState? { panels[batch]?.model.card }
    func pendingUndo(_ batch: BatchID) -> Task<Void, Never>? { undos[batch] }
    func isLingering(_ batch: BatchID) -> Bool { timers[batch]?.deadline != nil }

    func visibleButtons(_ batch: BatchID) -> [ResultCardModel.Button] {
        guard let model = panels[batch]?.model, let snapshot = model.snapshot else { return [] }
        return model.card.visible(ResultCardModel(snapshot))
    }
}
