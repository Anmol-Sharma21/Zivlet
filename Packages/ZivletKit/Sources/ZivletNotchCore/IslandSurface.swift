/// What the island shows (design/19 §4.1): nothing, the small resting shape, a one-line toast, or the full card.
public enum IslandSurface: Sendable, Equatable, Hashable, CaseIterable {
    case hidden, collapsed, toast, expanded
}
