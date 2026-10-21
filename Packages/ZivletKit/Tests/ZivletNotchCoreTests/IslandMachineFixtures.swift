import ZivletNotchCore

extension IslandRequest {
    static func hud(_ resting: IslandSurface, display: UInt32 = 1, closable: Bool = false) -> IslandRequest {
        IslandRequest(client: .hud, display: display, resting: resting, hoverSurface: .expanded, closable: closable)
    }
}

extension IslandMachine {
    /// A machine showing `resting` whose host has measured 108 pt of content.
    static func showing(_ resting: IslandSurface, at t: Duration, closable: Bool = false) -> IslandMachine {
        IslandMachine().handling(.request(.hud(resting, closable: closable), now: t)).0
            .handling(.contentHeightChanged(108, now: t)).0
    }

    /// Applies the events in order and keeps the last machine.
    func after(_ events: [IslandEvent]) -> IslandMachine {
        events.reduce(self) { machine, event in machine.handling(event).0 }
    }
}
