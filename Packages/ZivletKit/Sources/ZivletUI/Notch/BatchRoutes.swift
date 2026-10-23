import CoreGraphics
import ZivletCore

/// Which presenter shows each batch (D-M5a-8, design/19 §7). The placement is chosen at the drop, but snapshots
/// arrive by `BatchID` and the ID comes back asynchronously, so each drop enqueues a pending route (point, time,
/// route) and the first snapshot of an unknown batch claims the oldest one; later snapshots look the route up. A
/// retry enqueues its source batch's route with the new anchor. A batch nobody prepared takes the default route.
/// Like `ResultHUD`, this assumes batches start in the order they were submitted.
public struct BatchRoutes: Sendable, Equatable {
    public typealias Route = HUDRoute

    /// What the first snapshot of a batch learns: its route, the drop point to open at, and whether it was new.
    public struct Claim: Sendable, Equatable {
        public let route: Route
        public let point: CGPoint?
        public let isNew: Bool
    }

    struct Pending: Sendable, Equatable {
        let point: CGPoint?
        /// When the drop happened, on the caller's monotonic clock (D-M5a-8).
        let at: Duration
        let route: Route
    }

    public private(set) var defaultRoute: Route
    private var pending: [Pending] = []
    private var routes: [BatchID: Route] = [:]

    public init(defaultRoute: Route) { self.defaultRoute = defaultRoute }

    /// Drops whose batch has not been seen yet.
    public var pendingCount: Int { pending.count }

    public func enqueuing(point: CGPoint?, at time: Duration, route: Route) -> BatchRoutes {
        var next = self
        next.pending.append(Pending(point: point, at: time, route: route))
        return next
    }

    /// A known batch keeps its route and consumes nothing; a new one takes the oldest pending route or the default.
    public func claiming(_ batch: BatchID) -> (BatchRoutes, Claim) {
        if let known = routes[batch] { return (self, Claim(route: known, point: nil, isNew: false)) }
        var next = self
        let drop = next.pending.isEmpty ? nil : next.pending.removeFirst()
        let route = drop?.route ?? defaultRoute
        next.routes[batch] = route
        return (next, Claim(route: route, point: drop?.point, isNew: true))
    }

    public func route(of batch: BatchID) -> Route? { routes[batch] }

    /// The batch's presenter cannot show it (the island has no display): its later snapshots go to `route`.
    public func rerouting(_ batch: BatchID, to route: Route) -> BatchRoutes {
        var next = self
        next.routes[batch] = route
        return next
    }

    /// Retry pressed on `source`: its new batch goes where the source went, opening at `anchor`.
    public func retrying(_ source: BatchID, anchor: CGPoint?, at time: Duration) -> BatchRoutes {
        enqueuing(point: anchor, at: time, route: routes[source] ?? defaultRoute)
    }

    /// The batch closed; a later snapshot with its ID would be treated as new.
    public func forgetting(_ batch: BatchID) -> BatchRoutes {
        var next = self
        next.routes[batch] = nil
        return next
    }

    /// The setting or the notch latch changed: later batches with no drop take the new default.
    public func withDefaultRoute(_ route: Route) -> BatchRoutes {
        var next = self
        next.defaultRoute = route
        return next
    }
}
