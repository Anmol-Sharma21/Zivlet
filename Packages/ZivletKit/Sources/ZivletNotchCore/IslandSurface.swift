/// What the island shows (design/19 §4.1): nothing, the small resting shape, a one-line toast, or the full card; and
/// for the Drop Box's tray (design/19 §8, D-M5b-6, D-M5b-17) a one-row drop target while a file drag rests at the
/// notch, and a sensor over the housing that takes hover and shows nothing a person can see.
public enum IslandSurface: Sendable, Equatable, Hashable, CaseIterable {
    case hidden, collapsed, toast, expanded, dropTarget, sensor

    /// Drawn where a person can see it: everything but `hidden` and the `sensor`.
    public var isVisible: Bool { self != .hidden && self != .sensor }
}
