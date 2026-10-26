import AppKit
import SwiftUI

/// The island's content tokens (19b §3.1, §3.3): one spacing grid, two text styles plus a caption, symbol sizes, the
/// ring and the bar. Shared by the notch HUD and the Drop Box (plan 16 D-M5b-22), so both read from one set. Surface
/// tokens are `IslandLook`; ink is `IslandInk`.
public enum IslandContentLook {
    /// A 4 pt grid (D-NL6).
    public enum Spacing {
        /// Between icon buttons; between a primary and a secondary line.
        public static let xs: CGFloat = 4
        /// Glyph to text; content below the housing; list row gap; tab side inset.
        public static let s: CGFloat = 8
        /// Toast side inset; card bottom inset; pill side inset.
        public static let m: CGFloat = 12
        /// Card side inset: the island's own token, so the inner radius follows it.
        public static let l = CGFloat(IslandLook.cardInset)
        /// The toast's row (as M5a).
        public static let rowHeight: CGFloat = 36
        /// The band under the housing that holds the tab (as M5a).
        public static let tabBand: CGFloat = 24

        public static let all: [CGFloat] = [xs, s, m, l, rowHeight, tabBand]
    }

    /// Two styles per surface (D-NL7); the caption only for "+2 more", notes and the undo reply.
    public enum TypeStyle {
        public static let primary = Font.system(size: 13, weight: .semibold)
        /// Tabular digits, so sizes and percents do not jitter; layout code measures with the same font.
        public static let secondaryFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        public static let secondary = Font(secondaryFont as CTFont)
        public static let caption = Font.system(size: 10, weight: .regular)
        public static let count = Font.system(size: 11, weight: .semibold)
    }

    public enum Symbol {
        public static let tab = Font.system(size: 13, weight: .semibold)
        public static let tabBox: CGFloat = 16
        public static let toast = Font.system(size: 15, weight: .semibold)
        public static let button = Font.system(size: 13, weight: .medium)
        /// The round hit area of an icon button.
        public static let buttonSide: CGFloat = 28
    }

    public enum Ring {
        public static let side: CGFloat = 16
        public static let lineWidth: CGFloat = 2.5
        /// The stroke's length, for the visible steps of progress (19b §6.2).
        public static var strokeLength: Double { Double(side - lineWidth) * .pi }
    }

    public enum Bar {
        public static let height: CGFloat = 3
    }

    public enum Card {
        /// The working card's two rows without the card's insets: a text line, a gap and a 28 pt button row.
        public static let workingHeight: CGFloat = 52
        /// A reason of up to two lines and the file name with the buttons beside them, without the card's insets.
        public static let failureHeight: CGFloat = 52
    }
}
