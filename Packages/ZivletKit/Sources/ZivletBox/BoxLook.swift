import CoreGraphics
import SwiftUI
import ZivletNotch

/// The Drop Box's own tokens (19c §3.1–§3.4): the panel, the grid and list, the docked tab and the tray. Spacing,
/// type, symbols and ink are the island's (`IslandContentLook`, `IslandInk`); surface values are `IslandLook`.
public enum BoxLook {
    private typealias Spacing = IslandContentLook.Spacing

    public enum Panel {
        /// `l` + five cells + four gaps + `l` = 384.
        public static let width =
            2 * IslandContentLook.Spacing.l + CGFloat(Grid.columns) * Grid.cell
            + CGFloat(Grid.columns - 1) * Grid.gap
        /// The header, one grid row and the action bar.
        public static let minHeight: CGFloat = 152
        public static let collapsedHeight: CGFloat = 88
        public static let radius = IslandLook.Radius.card
        public static let headerHeight: CGFloat = 28
        public static let barHeight: CGFloat = 28
        /// Header to grid, grid to bar.
        public static let sectionGap = IslandContentLook.Spacing.m
        /// The Share button, first in the action bar, in the panel's content view (origin bottom-left): where the
        /// share picker points.
        public static let shareAnchor = CGRect(
            x: IslandContentLook.Spacing.l, y: IslandContentLook.Spacing.l, width: IslandContentLook.Symbol.buttonSide,
            height: IslandContentLook.Symbol.buttonSide)
    }

    public enum Grid {
        public static let columns = 5
        public static let cell: CGFloat = 64
        public static let thumb: CGFloat = 48
        public static let thumbRadius: CGFloat = 8
        public static let gap = IslandContentLook.Spacing.s
        public static let nameGap = IslandContentLook.Spacing.xs
        /// 11 pt names are white, not 0.8: 6.2:1 on the worst glass instead of 4.6:1 (19c §3.2).
        public static let nameFont = Font.system(size: 11, weight: .regular)
        public static let nameOpacity = 1.0
        /// Name line height under the thumbnail, for the row height.
        public static let nameHeight: CGFloat = 14
        public static var rowHeight: CGFloat { thumb + nameGap + nameHeight }
    }

    public enum List {
        public static let rowHeight = IslandContentLook.Spacing.rowHeight
        public static let icon: CGFloat = 24
        public static let iconRadius: CGFloat = 6
    }

    public enum Selection {
        public static let fill = 0.14
        public static let radius: CGFloat = 8
    }

    /// The tray's "+6" tile rests at the selection fill, so hover and press go one step brighter.
    public enum Tile {
        public static let hover = IslandIconButtonFill.pressed
        public static let pressed = 0.3
    }

    /// A missing cell or row; the badge stays fully visible.
    public static let missingOpacity = 0.4
    /// The content behind the drop target (19c D-BL7).
    public static let dropDim = 0.4

    public enum Badge {
        public static let symbol = Font.system(size: 10, weight: .semibold)
        /// The glyph is fitted into this square inside the circle, so wide symbols (the offline drive) keep a margin.
        public static let glyph: CGFloat = 9
        public static let circle: CGFloat = 16
        public static let circleOpacity = 0.6
    }

    public enum Empty {
        public static let symbol = Font.system(size: 28, weight: .regular)
        public static let symbolOpacity = 0.6
    }

    public enum Tab {
        public static let width: CGFloat = 28
        public static let height: CGFloat = 64
        /// Rounded only on the side away from the screen edge.
        public static let radius: CGFloat = 14
        /// During a drag over it the tab widens to show the drop symbol.
        public static let dropWidth: CGFloat = 48
    }

    public enum Tray {
        public static let thumb: CGFloat = 40
        public static let thumbRadius: CGFloat = 8
        public static let maxThumbs = 6
        public static let dropTargetWidth: CGFloat = 360
        public static let compactWidth: CGFloat = 380
        public static let compactMaxHeight: CGFloat = 320
    }

    /// 19c D-BL11, D-BL12: the entry scale, the Reduce Motion fade and the thumbnail fade.
    public enum Motion {
        public static let enterScale = 0.96
        public static let fade = 0.18
        public static let thumbnailFade = 0.12
    }
}
