import AppKit
import SwiftUI
import ZivletNotchCore
import os

/// The island's owner (D-N8, D-M5a-9): built once by the app from one provider and given to every client. It keeps
/// a pre-warmed host and a machine per display, the arbiter between clients, and alone handles display changes
/// (design/19 §5.2). Clients file requests; the wheel, the menu command and Reduce Motion arrive here too.
public final class IslandHosts {
    private let provider: any DisplayGeometryProvider
    private let clock: any MonotonicClock
    private let animation: IslandAnimation
    private let pointer: () -> CGPoint
    private var hosts: [UInt32: IslandHost] = [:]
    private var machines: [UInt32: IslandMachine] = [:]
    private var routers: [UInt32: IslandClientRouter] = [:]
    private var arbiter = IslandArbiter()
    private var clients: [IslandClientID: any IslandClient] = [:]
    private var reduceMotion = false
    private var finishSettings = IslandFinish.Settings.standard
    private var wheelShowing = false
    private var watch: Task<Void, Never>?
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")
    /// Each surface a display's island applies, with its frame (global, y up; `.zero` when hidden).
    public var onSurface: (UInt32, IslandSurface, CGRect) -> Void = { _, _, _ in }
    /// The current displays, the menu-bar display first.
    public private(set) var displayIDs: [UInt32] = []

    public init(
        provider: any DisplayGeometryProvider, clock: any MonotonicClock = SystemClock(),
        animation: IslandAnimation = .motion, pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.provider = provider
        self.clock = clock
        self.animation = animation
        self.pointer = pointer
        apply(displays: provider.displays)
        let changes = provider.changes
        watch = Task { [weak self] in
            for await displays in changes {
                guard let self else { return }
                self.displaysChanged(displays)
            }
        }
    }

    public func register(_ client: any IslandClient, as id: IslandClientID) { clients[id] = client }

    /// Sets `client`'s request on its display, or withdraws all of its requests when nil. The winner of each display
    /// it touches goes to that display's machine; the host measures the winner's content first.
    /// A request for a display that has no host yet is kept and shown when that display arrives.
    public func request(_ request: IslandRequest?, from client: IslandClientID) {
        if let request, request.client != client {
            return Self.logger.error("Island request from one client filed as another; ignored")
        }
        if let request, !displayIDs.contains(request.display) {
            Self.logger.error("Island request for display \(request.display) before it is known; kept until it arrives")
        }
        let before = Dictionary(displayIDs.map { ($0, arbiter.winner(on: $0)) }) { first, _ in first }
        arbiter = arbiter.updating(client, request)
        for id in displayIDs {
            let winner = arbiter.winner(on: id)
            guard id == request?.display || winner != before[id] ?? nil else { continue }
            route(winner, on: id)
        }
    }

    /// Withdraws `client`'s request on one display only; its islands on other displays stay.
    public func withdraw(_ client: IslandClientID, on display: UInt32) {
        let before = arbiter.winner(on: display)
        arbiter = arbiter.updating(client, on: display, nil)
        let winner = arbiter.winner(on: display)
        if winner != before { route(winner, on: display) }
    }

    /// The client's content changed on `display` (new text, Show Details, an undo reply): re-measured and redrawn.
    public func contentChanged(on display: UInt32) { hosts[display]?.contentChanged() }

    /// A drag of the client's content out of the island started or ended (D-N13): the island and its lingers are
    /// held until it ends.
    public func dragBegan(on display: UInt32) { step(.dragBegan(now: clock.now()), on: display) }
    public func dragEnded(on display: UInt32) { step(.dragEnded(now: clock.now()), on: display) }

    /// The client's spoken text changed (progress) without a new surface or height: only the text is copied.
    public func accessibilityChanged(on display: UInt32) { hosts[display]?.refreshAccessibility() }

    /// "Show Progress and Results" (D-N12): the island with items, the menu-bar display first, opens and takes keys.
    public func expandRequested() {
        guard let id = displayIDs.first(where: { arbiter.winner(on: $0) != nil }) else { return }
        expandRequested(on: id)
    }

    /// The island group's accessibility action (D-N12): that display's island opens and takes keys.
    public func expandRequested(on display: UInt32) { step(.expandRequested(now: clock.now()), on: display) }

    /// The wheel wins (W-8, D-M5b-8): drag types come off every island at once, before the machines step.
    public func wheelShown() {
        wheelShowing = true
        for host in hosts.values { host.dragsBlocked = true }
        broadcast(.wheelShown(now: clock.now()))
    }

    public func wheelHidden() {
        wheelShowing = false
        for host in hosts.values { host.dragsBlocked = false }
        broadcast(.wheelHidden(now: clock.now()))
    }

    public func reduceMotionChanged(_ on: Bool) {
        reduceMotion = on
        broadcast(.reduceMotionChanged(on, now: clock.now()))
    }

    /// Reduce Transparency or Increase Contrast changed (19b D-NL3): a shown island changes its finish at once, a
    /// hidden one at its next surface.
    public func finishSettingsChanged(_ settings: IslandFinish.Settings) {
        finishSettings = settings
        for host in hosts.values { host.finishSettings = settings }
    }

    /// Speaks `text` with VoiceOver; high priority interrupts (failures), medium waits.
    public func announce(_ text: String, highPriority: Bool) {
        let priority: NSAccessibilityPriorityLevel = highPriority ? .high : .medium
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: priority.rawValue])
    }

    public var hasItems: Bool { displayIDs.contains { arbiter.winner(on: $0) != nil } }
    public var visibleDisplays: [UInt32] { displayIDs.filter { hosts[$0]?.isVisible == true } }
    public func surface(on display: UInt32) -> IslandSurface { machines[display]?.surface ?? .hidden }
    public func activeClient(on display: UInt32) -> IslandClientID? { arbiter.winner(on: display)?.client }
    public func host(on display: UInt32) -> IslandHost? { hosts[display] }
    public func display(_ id: UInt32) -> DisplayGeometry? { hosts[id]?.display }

    /// Stops watching displays and orders every island out.
    public func close() {
        watch?.cancel()
        for host in hosts.values { host.close() }
    }

    /// Hosts of removed displays are destroyed, new displays get a pre-warmed host, the others are laid out again;
    /// every client learns the new set and the replacement of each removed display (the menu-bar display).
    ///
    /// An empty list (sleep, a reconfiguration in progress, every screen rejected) changes nothing: the islands and
    /// the requests stay until a list with a display arrives, so nothing a client filed is lost.
    func displaysChanged(_ displays: [DisplayGeometry]) {
        guard !displays.isEmpty else {
            return Self.logger.error("Display change with no displays: the islands wait for the next one")
        }
        let ids = displays.map(\.id)
        let removed = displayIDs.filter { !ids.contains($0) }
        for id in removed { remove(id) }
        apply(displays: displays)
        var replacing: [UInt32: UInt32] = [:]
        if let first = ids.first { for id in removed { replacing[id] = first } }
        for client in clients.values { client.displaysChanged(ids, replacing: replacing) }
    }

    private func apply(displays: [DisplayGeometry]) {
        for display in displays {
            if let host = hosts[display.id] { host.update(display: display) } else { add(display) }
        }
        displayIDs = displays.map(\.id)
    }

    private func add(_ display: DisplayGeometry) {
        let router = IslandClientRouter()
        router.current = clients[.hud]
        let host = IslandHost(display: display, client: router, motion: animation, clock: clock, pointer: pointer)
        host.finishSettings = finishSettings
        host.dragsBlocked = wheelShowing
        host.tracking.dropHandler = { [weak router] in router?.dropHandler }
        let id = display.id
        host.onEvent = { [weak self] event in self?.step(event, on: id) }
        host.onSurface = { [weak self] surface, frame in self?.onSurface(id, surface, frame) }
        hosts[id] = host
        routers[id] = router
        var machine = IslandMachine()
        if reduceMotion { machine = machine.handling(.reduceMotionChanged(true, now: clock.now())).0 }
        if wheelShowing { machine = machine.handling(.wheelShown(now: clock.now())).0 }
        machines[id] = machine
        host.curves = machine.motion
        if let waiting = arbiter.winner(on: id) { route(waiting, on: id) }
    }

    private func remove(_ id: UInt32) {
        hosts.removeValue(forKey: id)?.close()
        machines[id] = nil
        routers[id] = nil
        for client in IslandClientID.allCases { arbiter = arbiter.updating(client, on: id, nil) }
    }

    private func route(_ winner: IslandRequest?, on id: UInt32) {
        if let winner, let client = clients[winner.client] { routers[id]?.current = client }
        hosts[id]?.contentChanged()
        step(.request(winner, now: clock.now()), on: id)
    }

    private func broadcast(_ event: IslandEvent) {
        for id in displayIDs { step(event, on: id) }
    }

    private func step(_ event: IslandEvent, on id: UInt32) {
        guard let machine = machines[id], let host = hosts[id] else { return }
        let (next, effects) = machine.handling(event)
        machines[id] = next
        host.curves = next.motion
        host.apply(effects)
    }
}

/// The client a host draws: the winner of its display, kept after a withdrawal so the fade-out still has content.
final class IslandClientRouter: IslandClient {
    weak var current: (any IslandClient)?

    /// The current client, when it takes drops (D-M5b-7).
    var dropHandler: (any IslandDropHandling)? { current as? any IslandDropHandling }

    func content(for surface: IslandSurface, display: UInt32) -> AnyView {
        current?.content(for: surface, display: display) ?? AnyView(EmptyView())
    }

    func accessibilityLabel(display: UInt32) -> String { current?.accessibilityLabel(display: display) ?? "" }
    func accessibilityValue(display: UInt32) -> String { current?.accessibilityValue(display: display) ?? "" }
    var accessibilityActionName: String { current?.accessibilityActionName ?? "" }
    func accessibilityActionPerformed(display: UInt32) { current?.accessibilityActionPerformed(display: display) }
    func held(_ held: Bool, display: UInt32, now: Duration) { current?.held(held, display: display, now: now) }
    func closeRequested(display: UInt32) { current?.closeRequested(display: display) }
    func displaysChanged(_ ids: [UInt32], replacing: [UInt32: UInt32]) {}
    func surfaceChanged(_ surface: IslandSurface, display: UInt32) {
        current?.surfaceChanged(surface, display: display)
    }
}
