/// What the Drop Box panel shows (P2-55 §9.1, 19c §4.1): a base state, an optional overlay that interrupts it, the
/// dock edge it remembers, and the counts that raise Attention or show the empty hint. Pure and immutable; the table
/// test holds one row per state and event.
public struct BoxPresentation: Sendable, Equatable {
    public enum Base: Sendable, Equatable {
        case hidden
        case docked(DockEdge)
        case collapsed
        case expanded
    }

    public enum Overlay: Sendable, Equatable {
        /// A file drag is over the panel; "Add 3".
        case dropTarget(count: Int)
        /// A bulk action runs; the bar shows its progress and Cancel.
        case busy(verb: String, fraction: Double)
        /// The action bar became one question line.
        case confirm(ConfirmKind)
    }

    public let base: Base
    public let overlay: Overlay?
    /// The edge the panel returns to when it steps down (Esc) or is shown again; nil when it floats free.
    public let dock: DockEdge?
    public let missing: Int
    public let isEmpty: Bool

    public init(
        base: Base = .hidden, overlay: Overlay? = nil, dock: DockEdge? = nil, missing: Int = 0, isEmpty: Bool = false
    ) {
        self.base = base
        self.overlay = overlay
        self.dock = dock
        self.missing = max(0, missing)
        self.isEmpty = isEmpty
    }

    /// Some items are missing, in the Trash or offline (19c §4.1 Attention).
    public var needsAttention: Bool { missing > 0 }

    /// A drop lands only while the drop target shows.
    public var acceptsDrop: Bool {
        if case .dropTarget = overlay { return true }
        return false
    }

    public func handling(_ event: BoxPresentationEvent) -> (BoxPresentation, [BoxPresentationEffect]) {
        switch event {
        case .show: return moving(to: base == .hidden ? (dock.map(Base.docked) ?? .expanded) : .expanded)
        case .hide: return moving(to: .hidden)
        case .dock(let edge): return docking(edge)
        case .undock: return undocking()
        case .click: return isSmall ? moving(to: .expanded) : (self, [])
        case .escape: return escaping()
        case .dragEntered(let count): return enteringDrag(count)
        case .dragExited: return acceptsDrop ? (with(overlay: .some(nil)), []) : (self, [])
        case .dropped: return dropping()
        case .busyStarted(let verb): return startingBusy(verb)
        case .progress(let fraction): return progressing(fraction)
        case .busyEnded: return isBusy ? (with(overlay: .some(nil)), []) : (self, [])
        case .confirmRequested(let kind): return requestingConfirm(kind)
        case .confirmAnswered(let yes): return answering(yes)
        case .itemsChanged(let count, let missing): return (with(missing: missing, isEmpty: count == 0), [])
        }
    }
}

// MARK: - Rules

extension BoxPresentation {
    /// The docked tab or the collapsed card: a click opens the full panel.
    private var isSmall: Bool {
        switch base {
        case .docked, .collapsed: true
        case .hidden, .expanded: false
        }
    }

    /// A bulk action shows its progress: only Cancel applies.
    public var isBusy: Bool {
        if case .busy = overlay { return true }
        return false
    }

    private var confirmKind: ConfirmKind? {
        if case .confirm(let kind) = overlay { return kind }
        return nil
    }

    /// A new base: a confirmation only lives on the expanded card, and nothing lives on a hidden panel.
    private func moving(to next: Base) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard next != base else { return (self, []) }
        let keepsOverlay = next == .expanded || (next != .hidden && confirmKind == nil)
        let moved = with(base: next, overlay: keepsOverlay ? .some(overlay) : .some(nil))
        return (moved, next == .hidden ? [.dismiss, .persist] : [.present, .persist])
    }

    private func docking(_ edge: DockEdge) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard base != .hidden else { return (self, []) }
        let (moved, effects) = with(dock: .some(edge)).moving(to: .docked(edge))
        return (moved, effects.isEmpty ? [.persist] : effects)
    }

    private func undocking() -> (BoxPresentation, [BoxPresentationEffect]) {
        guard let dock else { return (self, []) }
        let free = with(dock: .some(nil))
        return base == .docked(dock) ? free.moving(to: .expanded) : (free, [.persist])
    }

    private func escaping() -> (BoxPresentation, [BoxPresentationEffect]) {
        switch overlay {
        case .confirm: return (with(overlay: .some(nil)), [])
        case .busy: return (self, [.cancelBusy])
        case .dropTarget: return (self, [])
        case nil: break
        }
        switch base {
        case .expanded: return moving(to: dock.map(Base.docked) ?? .collapsed)
        case .collapsed: return moving(to: .hidden)
        case .hidden, .docked: return (self, [])
        }
    }

    private func enteringDrag(_ count: Int) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard base != .hidden, overlay == nil || acceptsDrop else { return (self, []) }
        return (with(overlay: .some(.dropTarget(count: max(0, count)))), [])
    }

    private func dropping() -> (BoxPresentation, [BoxPresentationEffect]) {
        guard acceptsDrop else { return (self, []) }
        return with(overlay: .some(nil)).moving(to: .expanded)
    }

    private func startingBusy(_ verb: String) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard base != .hidden, !acceptsDrop else { return (self, []) }
        return (with(overlay: .some(.busy(verb: verb, fraction: 0))), [])
    }

    private func progressing(_ fraction: Double) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard case .busy(let verb, _) = overlay else { return (self, []) }
        let clamped = fraction.isNaN ? 0 : min(max(fraction, 0), 1)
        return (with(overlay: .some(.busy(verb: verb, fraction: clamped))), [])
    }

    private func requestingConfirm(_ kind: ConfirmKind) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard base == .expanded, overlay == nil || confirmKind != nil else { return (self, []) }
        return (with(overlay: .some(.confirm(kind))), [])
    }

    private func answering(_ yes: Bool) -> (BoxPresentation, [BoxPresentationEffect]) {
        guard let kind = confirmKind else { return (self, []) }
        return (with(overlay: .some(nil)), yes ? [.confirmed(kind)] : [])
    }

    private func with(
        base: Base? = nil, overlay: Overlay?? = nil, dock: DockEdge?? = nil, missing: Int? = nil, isEmpty: Bool? = nil
    ) -> BoxPresentation {
        BoxPresentation(
            base: base ?? self.base, overlay: overlay ?? self.overlay, dock: dock ?? self.dock,
            missing: missing ?? self.missing, isEmpty: isEmpty ?? self.isEmpty)
    }
}

extension BoxPresentation.Base {
    /// The value `boxes.json` holds: "hidden", "collapsed", "expanded", "docked-left" or "docked-right".
    public var stored: String {
        switch self {
        case .hidden: "hidden"
        case .collapsed: "collapsed"
        case .expanded: "expanded"
        case .docked(let edge): "docked-\(edge.rawValue)"
        }
    }

    /// A stored value; anything missing or unknown is hidden.
    public init(stored: String?) {
        switch stored {
        case "collapsed": self = .collapsed
        case "expanded": self = .expanded
        case "docked-left": self = .docked(.left)
        case "docked-right": self = .docked(.right)
        default: self = .hidden
        }
    }
}
