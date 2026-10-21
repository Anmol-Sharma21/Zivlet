/// Who wants the island (design/19 §4.1, §8). Declared in priority order: the picker beats the tray, the tray beats
/// the HUD. Only `.hud` has a client in M5a; the others are tested with fakes (D-M5a-7).
public enum IslandClientID: Sendable, Hashable, Comparable, CaseIterable {
    case hud, tray, picker
}

/// What a client asks of the island on one display: the surface it rests on without hover, the surface hover or
/// focus reveals, and whether Escape on the open card should ask the client to close it. No content height: the host
/// measures that (design/19 §3.4).
public struct IslandRequest: Sendable, Equatable {
    public let client: IslandClientID
    public let display: UInt32
    public let resting: IslandSurface
    public let hoverSurface: IslandSurface
    public let closable: Bool

    public init(
        client: IslandClientID, display: UInt32, resting: IslandSurface, hoverSurface: IslandSurface,
        closable: Bool = false
    ) {
        self.client = client
        self.display = display
        self.resting = resting
        self.hoverSurface = hoverSurface
        self.closable = closable
    }
}
