import Foundation
import ZivletActions
import ZivletCore
import ZivletNotchCore
import ZivletRuntime

/// The Notch HUD's state (design/19 §4.3, §4.4, §5.5; D-N7, D-N13, D-M5a-3). A pure value: conversion batches and
/// action results become items per display, each with its own linger; every transition returns a new board. It reads
/// no clock: each call carries a monotonic `now`, and `nextDeadline` says when to call `expiring(now:)` again.
public struct NotchHUDBoard: Sendable, Equatable {
    /// The stepped glyph of a job of unknown length advances at most this often (D-N7); progress redraws no faster.
    public static let stepInterval = Duration.milliseconds(250)
    static let stepCount = 8
    /// A failure rests as a toast this long, then waits in the tab until closed.
    static let failureToast = Duration.seconds(4)
    /// With VoiceOver or Switch Control running, toasts stay three times as long (D-N13).
    static let assistiveFactor = 3
    static let maxRows = 5

    struct Drawn: Sendable, Equatable {
        let tab: TabContent
        let at: Duration
    }

    private(set) var items: [UInt32: [NotchHUDItem]] = [:]
    private var held: Set<UInt32> = []
    /// The id the next action result gets.
    private(set) var nextAction = 0
    private var drawn: [UInt32: Drawn] = [:]
    /// The `now` of the last transition, for the stepped glyph.
    private(set) var now = Duration.zero
    public private(set) var assistiveTech: Bool
    /// What to announce for the last transition; each event is announced once.
    public private(set) var announcements: [Announcement] = []
    /// The last transition changed the drawn tab: a new shape, or a new percent or step ≥ 250 ms after the last one.
    public private(set) var redraw = false

    public init(assistiveTech: Bool = false) { self.assistiveTech = assistiveTech }

    /// The same board with VoiceOver or Switch Control on or off; lingers started afterwards follow it.
    public func assisted(_ on: Bool) -> NotchHUDBoard {
        var next = self
        next.assistiveTech = on
        return next
    }

    public func updating(_ snapshot: BatchSnapshot, display: UInt32, now: Duration) -> NotchHUDBoard {
        transition(now) { $0.apply(snapshot, display: display) }
    }

    /// An action's result; a cancel shows nothing.
    public func updating(_ action: ActionResult, display: UInt32, now: Duration) -> NotchHUDBoard {
        transition(now) { $0.apply(action, display: display) }
    }

    /// The island's hold changed (pointer, accessibility focus, a drag from it): lingers pause, and restart in full
    /// when it ends.
    public func holding(_ isHeld: Bool, display: UInt32, now: Duration) -> NotchHUDBoard {
        transition(now) { board in
            if isHeld { board.held.insert(display) } else { board.held.remove(display) }
            board.mapItems(on: display) { item in
                guard let linger = item.linger, !item.paused else { return item }
                var next = item
                next.linger = isHeld ? linger.hovered(at: now) : linger.unhovered(at: now)
                return next
            }
        }
    }

    /// Undo was pressed on the item: its linger waits for the reply.
    public func pausing(_ id: NotchHUDItemID) -> NotchHUDBoard {
        let now = self.now
        return transition(now) { board in
            board.mapItem(id) { item in
                var next = item
                next.paused = true
                next.linger = item.linger?.hovered(at: now)
                return next
            }
        }
    }

    /// The undo replied: the full linger starts again, unless the island is held.
    public func restarting(_ id: NotchHUDItemID, now: Duration) -> NotchHUDBoard {
        transition(now) { board in
            let heldDisplays = board.held
            board.mapItem(id) { display, item in
                var next = item
                next.paused = false
                if !heldDisplays.contains(display) { next.linger = item.linger?.started(at: now) }
                return next
            }
        }
    }

    public func closing(_ id: NotchHUDItemID, now: Duration) -> NotchHUDBoard {
        transition(now) { board in
            for display in board.items.keys { board.items[display]?.removeAll { $0.id == id } }
        }
    }

    /// Escape on a closable card, or the card's Close: everything on the display goes.
    public func closingAll(on display: UInt32) -> NotchHUDBoard {
        transition(now) { $0.items[display] = nil }
    }

    /// Lingers that ran out: a saved item or a toast leaves, a failure's toast becomes the tab's error glyph.
    public func expiring(now: Duration) -> NotchHUDBoard {
        transition(now) { board in
            for display in board.items.keys {
                board.items[display] = board.items[display]?.compactMap { item in
                    guard let linger = item.linger, linger.expired(at: now) else { return item }
                    guard item.isFailure else { return nil }
                    var next = item
                    next.waits = true
                    next.linger = nil
                    return next
                }
            }
        }
    }

    /// A removed display's items move to its replacement (design/19 §5.2).
    public func movingItems(from removed: UInt32, to replacement: UInt32) -> NotchHUDBoard {
        guard removed != replacement else { return self }
        return transition(now) { board in
            let moving = board.items[removed] ?? []
            board.items[removed] = nil
            board.held.remove(removed)
            board.drawn[removed] = nil
            if !moving.isEmpty { board.items[replacement, default: []].append(contentsOf: moving) }
        }
    }

    public func isHeld(on display: UInt32) -> Bool { held.contains(display) }

    /// The displays that have items.
    public var displays: [UInt32] { items.filter { !$0.value.isEmpty }.keys.sorted() }

    /// The earliest linger deadline or stepped-glyph step; nil when nothing changes on its own.
    public var nextDeadline: Duration? {
        let all = items.values.joined()
        let lingers = all.compactMap { $0.linger?.deadline }
        let steps = all.filter(\.isWorking).compactMap { item in
            item.indeterminateSince.map { $0 + Self.stepInterval * (steps(since: $0) + 1) }
        }
        return (lingers + steps).min()
    }

    /// Whole steps of the stepped glyph since `since`.
    func steps(since: Duration) -> Int { max(0, Int(((now - since) / Self.stepInterval).rounded(.down))) }
}

// Transitions: every public change runs through `transition`, which clears the last announcements and works out
// whether the drawn tab changes.
extension NotchHUDBoard {
    private func transition(_ now: Duration, _ change: (inout NotchHUDBoard) -> Void) -> NotchHUDBoard {
        var next = self
        next.now = max(self.now, now)
        next.announcements = []
        change(&next)
        next.items = next.items.filter { !$0.value.isEmpty }
        next.updateDrawn()
        return next
    }

    private mutating func apply(_ snapshot: BatchSnapshot, display: UInt32) {
        let id = NotchHUDItemID.batch(snapshot.batch)
        let found = locate(id)
        let old = found?.item
        let home = found?.display ?? display
        var item = old ?? NotchHUDItem(id: id, kind: .batch(snapshot))
        item.kind = .batch(snapshot)
        item.indeterminateSince = snapshot.isIndeterminate ? (item.indeterminateSince ?? now) : nil
        let wasFinished = old?.snapshot?.isFinished ?? false
        if snapshot.isFinished, !wasFinished {
            announcements.append(NotchHUDCopy.announcement(finished: snapshot))
            item = startingLinger(item, on: home)
        } else if old == nil {
            announcements.append(Announcement(text: NotchHUDCopy.started(snapshot), highPriority: false))
        }
        if let found { replace(found, with: item) } else { items[home, default: []].append(item) }
    }

    private mutating func apply(_ action: ActionResult, display: UInt32) {
        if case .cancelled = action { return }
        let item = NotchHUDItem(id: .action(nextAction), kind: .action(action))
        nextAction += 1
        announcements.append(Announcement(text: NotchHUDCopy.action(action), highPriority: action.card != nil))
        items[display, default: []].append(startingLinger(item, on: display))
    }

    private func startingLinger(_ item: NotchHUDItem, on display: UInt32) -> NotchHUDItem {
        guard let duration = lingerDuration(item) else { return item }
        var next = item
        let timer = LingerTimer(duration: duration)
        next.linger = held.contains(display) || item.paused ? timer : timer.started(at: now)
        return next
    }

    /// How long the item rests as a toast: 4 s for a saved batch or a failure's toast, 1.5 s or 4 s with Undo for an
    /// action; three times as long with assistive tech.
    private func lingerDuration(_ item: NotchHUDItem) -> Duration? {
        let base: Duration
        switch item.kind {
        case .batch(let snapshot):
            guard snapshot.isFinished else { return nil }
            base = item.isFailure ? Self.failureToast : ResultCardModel.successLinger
        case .action(let result):
            if result.card != nil {
                base = Self.failureToast
            } else {
                base = result.undo == nil ? ActionHUD.toastLinger : ActionHUD.undoLinger
            }
        }
        return assistiveTech ? base * Self.assistiveFactor : base
    }

    private typealias Found = (display: UInt32, index: Int, item: NotchHUDItem)

    private func locate(_ id: NotchHUDItemID) -> Found? {
        for (display, list) in items {
            if let index = list.firstIndex(where: { $0.id == id }) { return (display, index, list[index]) }
        }
        return nil
    }

    private mutating func replace(_ found: Found, with item: NotchHUDItem) {
        guard var list = items[found.display], list.indices.contains(found.index) else { return }
        list[found.index] = item
        items[found.display] = list
    }

    private mutating func mapItems(on display: UInt32, _ change: (NotchHUDItem) -> NotchHUDItem) {
        items[display] = items[display]?.map(change)
    }

    private mutating func mapItem(_ id: NotchHUDItemID, _ change: (NotchHUDItem) -> NotchHUDItem) {
        mapItem(id) { _, item in change(item) }
    }

    private mutating func mapItem(_ id: NotchHUDItemID, _ change: (UInt32, NotchHUDItem) -> NotchHUDItem) {
        guard let found = locate(id) else { return }
        replace(found, with: change(found.display, found.item))
    }

    /// A tab redraws when its shape changes, or when its percent or step changes ≥ 250 ms after the last redraw.
    private mutating func updateDrawn() {
        redraw = false
        for display in Set(items.keys).union(drawn.keys) {
            guard let tab = tab(on: display) else {
                if drawn.removeValue(forKey: display) != nil { redraw = true }
                continue
            }
            if let last = drawn[display], last.tab.sameShape(as: tab) {
                guard last.tab.ring.shown != tab.ring.shown, now - last.at >= Self.stepInterval else { continue }
            }
            drawn[display] = Drawn(tab: tab, at: now)
            redraw = true
        }
    }
}
