/// Where progress and results show (design/19 §6, OWN-HUD-1): at the notch (the top-centre pill on a Mac without
/// one), near the drop (today's card), or automatically, which means the notch on a Mac with a built-in notch.
public enum HUDPlacement: String, Sendable, Codable, CaseIterable {
    case automatic, notch, nearDrop

    /// The placement this Mac uses. `hasBuiltInNotch` is the latch of design/19 §3.2, not "a notch display is
    /// connected now", so closing the lid does not change it.
    public func resolved(hasBuiltInNotch: Bool) -> HUDPlacement {
        switch self {
        case .automatic: hasBuiltInNotch ? .notch : .nearDrop
        case .notch, .nearDrop: self
        }
    }
}

/// HUD group (design/19 §6): stored as `settings.hud.v1`; an M4 store has none and loads as `.automatic`.
public struct HUDGroup: Sendable, Equatable, Codable {
    public var placement = HUDPlacement.automatic

    public init() {}
}
