import ZivletSettings

/// Which presenter shows a batch or an action: the notch island or today's card near the drop (D-M5a-2).
public enum HUDRoute: Sendable, Equatable {
    case notch, nearDrop

    /// A resolved placement; `.automatic` never reaches here, and would mean the notch.
    init(_ placement: HUDPlacement) { self = placement == .nearDrop ? .nearDrop : .notch }

    /// The island cannot show anything without a display (every screen asleep or rejected): the card near the drop
    /// takes over, so a result is never filed where nothing draws it.
    public func usable(islandHasDisplay: Bool) -> HUDRoute { self == .notch && !islandHasDisplay ? .nearDrop : self }
}

/// The demo's `-ZivletHUDPlacement notch|nearDrop` (D-M5a-10): read by the app's settings wiring for one run, never
/// stored, so the picker and the diagnostics show only what the person chose.
public enum PlacementOverride {
    public static let key = "ZivletHUDPlacement"

    /// The override in the launch arguments' domain; any other value is ignored.
    public static func parse(_ arguments: [String: Any]) -> HUDPlacement? {
        guard let raw = arguments[key] as? String, let placement = HUDPlacement(rawValue: raw),
            placement != .automatic
        else { return nil }
        return placement
    }

    /// Where a batch or action with no route of its own goes: `override ?? settings.hud.placement`, resolved.
    public static func defaultRoute(override: HUDPlacement?, settings: ZivletSettings.Settings, hasBuiltInNotch: Bool)
        -> HUDRoute
    {
        HUDRoute((override ?? settings.hud.placement).resolved(hasBuiltInNotch: hasBuiltInNotch))
    }
}
