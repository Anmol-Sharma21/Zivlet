import ZivletNotchCore

/// The island's surface tokens (19b §3.2, §3.5): finish, scrim, fade, flare, radii and outline. Content tokens
/// (spacing, type, symbols, ink) are `NotchLook` and `NotchInk` in ZivletUI.
public enum IslandLook {
    /// Black under the content on glass: the probe's worst surface (pill and tab size over white) stays above 4.5:1
    /// for secondary text with it (19b §4.2 P7).
    public static let scrim = 0.5
    /// Linear luminance of the lightest glass measured with the scrim over a white window (0.102), plus margin. The
    /// ink's contrast tests use it; task D18 re-measures the built island.
    public static let worstGlassLuminance = 0.12
    /// The solid finish of Reduce Transparency and Increase Contrast: sRGB grey 0.11 (#1C1C1C).
    public static let solidGrey = 0.11
    /// From black at the housing's bottom edge to the finish this much lower.
    public static let fade = 16.0
    /// The concave curve that brings the top edge in to the body on a notch display (D-NL4).
    public static let flare = 6.0

    public enum Outline {
        public static let width = 1.0
        public static let opacity = 0.5
    }

    /// Continuous corner radii (D-NL5).
    public enum Radius {
        public static var tab: Double { IslandLayout.Metrics.collapsedRadius }
        public static var toast: Double { IslandLayout.Metrics.toastRadius }
        public static var card: Double { IslandLayout.Metrics.expandedRadius }
        /// Anything inside the card, concentric with it: the card radius minus the card's side inset (16).
        public static var inner: Double { card - 16 }
    }
}
