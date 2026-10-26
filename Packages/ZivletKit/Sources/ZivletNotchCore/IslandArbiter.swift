/// One island per display, several clients (design/19 §4.1, §8): each client's latest request per display is kept.
/// Requests that rest on a visible surface come first, by priority (picker > tray > HUD); only when there is none
/// does the highest-priority sensor win, so a tray at rest never hides the HUD's progress (D-M5b-6); requests that
/// rest hidden come last. A withdrawn request hands the island back to the next. The machine of a display receives
/// `.request(winner)` whenever the winner changes.
public struct IslandArbiter: Sendable, Equatable {
    private let requests: [UInt32: [IslandClientID: IslandRequest]]

    public init() { requests = [:] }

    private init(requests: [UInt32: [IslandClientID: IslandRequest]]) { self.requests = requests }

    /// The displays that have at least one request.
    public var displays: Set<UInt32> { Set(requests.keys) }

    public func winner(on display: UInt32) -> IslandRequest? {
        requests[display]?.max { Self.rank($0) < Self.rank($1) }?.value
    }

    /// Visible rests above sensors above hidden rests; inside each, the client's priority.
    private static func rank(_ entry: (key: IslandClientID, value: IslandRequest)) -> (Int, IslandClientID) {
        let rest = entry.value.resting
        return (rest.isVisible ? 2 : rest == .sensor ? 1 : 0, entry.key)
    }

    /// Sets `request` on its own display, or withdraws all of `client`'s requests when it is nil. A request filed
    /// under another client is ignored.
    public func updating(_ client: IslandClientID, _ request: IslandRequest?) -> IslandArbiter {
        guard let request else {
            return displays.reduce(self) { arbiter, display in arbiter.updating(client, on: display, nil) }
        }
        guard request.client == client else { return self }
        return updating(client, on: request.display, request)
    }

    /// Sets or withdraws `client`'s request on one display.
    public func updating(_ client: IslandClientID, on display: UInt32, _ request: IslandRequest?) -> IslandArbiter {
        if let request, request.client != client || request.display != display { return self }
        var onDisplay = requests[display] ?? [:]
        onDisplay[client] = request
        var all = requests
        all[display] = onDisplay.isEmpty ? nil : onDisplay
        return IslandArbiter(requests: all)
    }
}
