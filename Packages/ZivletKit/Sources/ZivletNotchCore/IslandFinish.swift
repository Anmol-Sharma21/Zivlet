import ZivletCore

/// How a surface of the island is filled (OWN-UI-1, 19b D-NL1, D-NL3, plan 14 D-ND2). Pure: the chrome only draws it.
///
/// On a notch display the collapsed tab stays solid black, one piece with the housing (D-N10). The toast and the card
/// are black down to the housing's bottom edge (`band`), then Liquid Glass. Without a notch every surface is glass
/// with no band. Reduce Transparency or Increase Contrast turns glass solid; Increase Contrast also outlines it.
public enum IslandFinish: Sendable, Equatable {
    case black(outline: Bool)
    case glass(band: Double)
    case solid(band: Double, outline: Bool)

    /// The display options that change the finish.
    public struct Settings: Sendable, Equatable {
        public let reduceTransparency: Bool
        public let increaseContrast: Bool

        public init(reduceTransparency: Bool, increaseContrast: Bool) {
            self.reduceTransparency = reduceTransparency
            self.increaseContrast = increaseContrast
        }

        public static let standard = Settings(reduceTransparency: false, increaseContrast: false)
    }

    /// `hidden` keeps `previous`: a surface fading out keeps the finish it had.
    public static func resolve(
        _ surface: IslandSurface, on display: DisplayGeometry, settings: Settings,
        previous: IslandFinish = .black(outline: false)
    ) -> IslandFinish {
        let outline = settings.increaseContrast
        let housing = NotchGeometry.housing(of: display)
        switch surface {
        case .hidden:
            return previous
        case .collapsed where housing != nil:
            return .black(outline: outline)
        case .collapsed, .toast, .expanded:
            let band = housing?.height ?? 0
            let solid = settings.reduceTransparency || settings.increaseContrast
            return solid ? .solid(band: band, outline: outline) : .glass(band: band)
        }
    }

    /// The 1 pt outline of Increase Contrast.
    public var outlined: Bool {
        switch self {
        case .black(let outline), .solid(_, let outline): outline
        case .glass: false
        }
    }

    /// The black band from the top edge to the housing's bottom; 0 on a pill and for the all-black tab.
    public var band: Double {
        switch self {
        case .black: 0
        case .glass(let band), .solid(let band, _): band
        }
    }

    public var isGlass: Bool {
        if case .glass = self { return true }
        return false
    }
}
