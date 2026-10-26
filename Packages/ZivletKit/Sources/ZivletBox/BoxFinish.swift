import ZivletNotchCore

/// How the Drop Box panel is filled (19c D-BL1, D-BL2): glass under the island's scrim; the solid grey of Reduce
/// Transparency; or solid with the outline under Increase Contrast. The rule is the island's floating finish.
nonisolated public enum BoxFinish: Sendable, Equatable {
    case glass, solid, contrast

    public static func resolve(_ settings: IslandFinish.Settings) -> BoxFinish {
        switch IslandFinish.floating(settings: settings) {
        case .solid(_, true), .black(true): .contrast
        case .solid, .black: .solid
        case .glass: .glass
        }
    }

    /// The island's finish value with no band, for `SurfaceFill`.
    public var islandFinish: IslandFinish {
        switch self {
        case .glass: .glass(band: 0)
        case .solid: .solid(band: 0, outline: false)
        case .contrast: .solid(band: 0, outline: true)
        }
    }

    public var outlined: Bool { self == .contrast }
}
