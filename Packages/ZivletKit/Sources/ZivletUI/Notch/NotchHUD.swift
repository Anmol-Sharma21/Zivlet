import AppKit
import Observation
import ZivletActions
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime
import os

/// What the island's views read: the board as last published, and the per-item state that changes after an item
/// appears (the card's undo reply, details and thumbnail; the action's undo reply).
@Observable
final class NotchHUDModel {
    var board = NotchHUDBoard()
    var cards: [BatchID: CardState] = [:]
    var actions: [Int: ActionHUDModel] = [:]
}

/// The Notch HUD (P2-116, design/19 §4.3, §5.4–§5.5, §7): the island's `.hud` client. It keeps the drop point of the
/// next batch or action, finds its display, updates the board, files the board's request with the one `IslandHosts`
/// the app built, wakes at the board's next deadline, posts its announcements and routes presses to the same
/// closures `ResultHUD` and `ActionHUD` use.
public final class NotchHUD: HUDPresenter, ActionPresenter {
    /// The card's buttons plus Cancel of a working batch.
    public enum Press: Sendable, Hashable, CaseIterable {
        case undo, reveal, open, copy, showDetails, retry, close, cancel

        init(_ button: ResultCardModel.Button) {
            switch button {
            case .undo: self = .undo
            case .reveal: self = .reveal
            case .open: self = .open
            case .copy: self = .copy
            case .showDetails: self = .showDetails
            case .retry: self = .retry
            case .close: self = .close
            }
        }
    }

    public var onCancel: (BatchID) -> Void = { _ in }
    public var onReveal: ([URL]) -> Void = { _ in }
    public var onOpen: ([URL]) -> Void = { _ in }
    public var onCopy: ([URL]) -> Void = { _ in }
    public var onRetry: (BatchID, CGPoint?) -> Void = { _, _ in }
    public var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }
    /// Posts a VoiceOver announcement; a test seam.
    var announce: (Announcement) -> Void
    /// Called at the top of every board change; a test seam.
    var onApply: () -> Void = {}

    let model = NotchHUDModel()
    private(set) var board = NotchHUDBoard()
    private(set) weak var hosts: IslandHosts?
    private let provider: any DisplayGeometryProvider
    let clock: any MonotonicClock
    private let signposter = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "hud")
    private var pending: [(point: CGPoint?, interval: OSSignpostIntervalState)] = []
    private(set) var anchors: [BatchID: CGPoint] = [:]
    var undos: [NotchHUDItemID: Task<Void, Never>] = [:]
    private var expiry: (deadline: Duration, task: Task<Void, Never>)?
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")

    public init(hosts: IslandHosts, provider: any DisplayGeometryProvider, clock: any MonotonicClock = SystemClock()) {
        self.hosts = hosts
        self.provider = provider
        self.clock = clock
        announce = { [weak hosts] in hosts?.announce($0.text, highPriority: $0.highPriority) }
        hosts.register(self, as: .hud)
    }

    /// The island has a display to show on. The app sends a batch or an action near the drop when it does not.
    public var canShow: Bool { display(for: nil) != nil }

    /// A drag of the result thumbnail out of the island started or ended: the island and its lingers hold until it
    /// ends (D-N13).
    public func dragChanged(_ began: Bool, display: UInt32) {
        if began { hosts?.dragBegan(on: display) } else { hosts?.dragEnded(on: display) }
    }

    /// VoiceOver or Switch Control started or stopped: toasts that start afterwards linger three times as long.
    public func assistiveTechChanged(_ on: Bool) { board = board.assisted(on) }

    public func prepare(near point: CGPoint?) {
        pending.append((point, signposter.beginInterval("drop→island")))
    }

    public func show(_ snapshot: BatchSnapshot) {
        let id = NotchHUDItemID.batch(snapshot.batch)
        let known = board.item(id)
        if known != nil, !snapshot.isFinished, drawsNothingNew(snapshot, id) { return }
        let drop: (point: CGPoint?, interval: OSSignpostIntervalState)? =
            known == nil && !pending.isEmpty ? pending.removeFirst() : nil
        guard let display = board.display(of: id) ?? display(for: drop?.point ?? nil) else {
            if let interval = drop?.interval { signposter.endInterval("drop→island", interval) }
            return Self.logger.error("Notch HUD has no display for a batch; it is not shown")
        }
        if known == nil {
            anchors[snapshot.batch] = drop?.point ?? nil
            if model.cards[snapshot.batch] == nil { model.cards[snapshot.batch] = CardState() }
        }
        apply(board.updating(snapshot, display: display, now: clock.now()))
        if let interval = drop?.interval { signposter.endInterval("drop→island", interval) }
        let wasFinished = known?.snapshot?.isFinished ?? false
        if snapshot.isFinished, !wasFinished, let first = snapshot.outputs.first {
            loadThumbnail(first.url, for: snapshot.batch)
        }
    }

    /// The island already draws and speaks what `snapshot` would (G-M5a-1, 19b §6.2). The key is compared with the
    /// published board's, not the latest applied one, so a step that came within 250 ms of the last redraw is still
    /// drawn by the next snapshot.
    private func drawsNothingNew(_ snapshot: BatchSnapshot, _ id: NotchHUDItemID) -> Bool {
        guard let drawn = model.board.item(id)?.visible else { return false }
        return drawn == VisibleKey(snapshot, ringSteps: NotchHUDBoard.ringSteps, barSteps: NotchHUDBoard.barSteps)
    }

    /// The batch leaves the island; the other items stay.
    public func close(_ batch: BatchID) { close(.batch(batch)) }

    public func show(_ result: ActionResult, near point: CGPoint?) {
        if case .cancelled = result { return }
        guard let display = display(for: point) else {
            return Self.logger.error("Notch HUD has no display for an action result; it is not shown")
        }
        let actionModel = ActionHUDModel()
        actionModel.present(result)
        model.actions[board.nextAction] = actionModel
        apply(board.updating(result, display: display, now: clock.now()))
    }

    func close(_ id: NotchHUDItemID) {
        undos.removeValue(forKey: id)?.cancel()
        forget(id)
        apply(board.closing(id, now: clock.now()))
    }

    func forget(_ id: NotchHUDItemID) {
        switch id {
        case .batch(let batch):
            model.cards[batch] = nil
            anchors[batch] = nil
        case .action(let index):
            model.actions[index] = nil
        }
    }

    /// Every board change goes through here: the views see it when the tab redraws or the layout changes, each
    /// display's request is filed or withdrawn, announcements are posted and the next deadline is scheduled.
    func apply(_ next: NotchHUDBoard) {
        onApply()
        let old = board
        board = next
        let displays = Set(old.displays).union(next.displays)
        let changed = displays.filter {
            old.request(on: $0) != next.request(on: $0) || old.shapes(on: $0) != next.shapes(on: $0)
        }
        let redrawn = next.redraw || !changed.isEmpty || old.toastLines != next.toastLines
        if redrawn { model.board = next }
        for display in displays.sorted() { sync(display, from: old, to: next) }
        // The spoken value follows what is drawn (progress at most every 250 ms), not only new surfaces (§5.5).
        if redrawn { for display in next.displays { hosts?.accessibilityChanged(on: display) } }
        for announcement in next.announcements { announce(announcement) }
        scheduleExpiry()
    }

    private func sync(_ display: UInt32, from old: NotchHUDBoard, to next: NotchHUDBoard) {
        let request = next.request(on: display)
        if request != old.request(on: display) {
            if let request { hosts?.request(request, from: .hud) } else { hosts?.withdraw(.hud, on: display) }
        } else if old.shapes(on: display) != next.shapes(on: display) {
            hosts?.contentChanged(on: display)
        }
    }

    /// One sleep for the board's earliest deadline on the one clock (D-N11); an early wake sleeps again.
    private func scheduleExpiry() {
        guard let deadline = board.nextDeadline else {
            expiry?.task.cancel()
            expiry = nil
            return
        }
        guard deadline != expiry?.deadline else { return }
        expiry?.task.cancel()
        let clock = self.clock
        let task = Task { [weak self] in
            while clock.now() < deadline {
                do { try await clock.sleep(until: deadline) } catch { return }
            }
            guard let self, self.expiry?.deadline == deadline else { return }
            self.expiry = nil
            self.apply(self.board.expiring(now: clock.now()))
        }
        expiry = (deadline, task)
    }

    /// The display that holds `point`, else the menu-bar display; nil when the island has no display at all.
    private func display(for point: CGPoint?) -> UInt32? {
        let shown = IslandLayout.display(for: point.map { Point2D(x: $0.x, y: $0.y) }, in: provider.displays)
        return shown?.id ?? hosts?.displayIDs.first
    }

    private func loadThumbnail(_ url: URL, for batch: BatchID) {
        Task { [weak self] in
            let image = await ThumbnailLoader.thumbnail(for: url)
            guard let self, let card = self.model.cards[batch] else { return }
            card.thumbnail = image
            if let display = self.board.display(of: .batch(batch)) { self.hosts?.contentChanged(on: display) }
        }
    }
}
