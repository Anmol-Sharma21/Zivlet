import SwiftUI
import ZivletNotch

/// The island's content tokens (19b §3.1, §3.3): one spacing grid, two text styles plus a caption, symbol sizes, the
/// ring and the bar. Surface tokens are `IslandLook`; ink is `NotchInk`.
enum NotchLook {
    /// A 4 pt grid (D-NL6).
    enum Spacing {
        /// Between icon buttons; between a primary and a secondary line.
        static let xs: CGFloat = 4
        /// Glyph to text; content below the housing; list row gap; tab side inset.
        static let s: CGFloat = 8
        /// Toast side inset; card bottom inset; pill side inset.
        static let m: CGFloat = 12
        /// Card side inset.
        static let l: CGFloat = 16
        /// The toast's row (as M5a).
        static let rowHeight: CGFloat = 36
        /// The band under the housing that holds the tab (as M5a).
        static let tabBand: CGFloat = 24

        static let all: [CGFloat] = [xs, s, m, l, rowHeight, tabBand]
    }

    /// Two styles per surface (D-NL7); the caption only for "+2 more", notes and the undo reply.
    enum TypeStyle {
        static let primary = Font.system(size: 13, weight: .semibold)
        static let secondary = Font.system(size: 12, weight: .regular).monospacedDigit()
        static let caption = Font.system(size: 10, weight: .regular)
        static let count = Font.system(size: 11, weight: .semibold)
    }

    enum Symbol {
        static let tab = Font.system(size: 13, weight: .semibold)
        static let tabBox: CGFloat = 16
        static let toast = Font.system(size: 15, weight: .semibold)
        static let button = Font.system(size: 13, weight: .medium)
        /// The round hit area of an icon button.
        static let buttonSide: CGFloat = 28
    }

    enum Ring {
        static let side: CGFloat = 16
        static let lineWidth: CGFloat = 2.5
        /// The stroke's length, for the visible steps of progress (19b §6.2).
        static var strokeLength: Double { Double(side - lineWidth) * .pi }
    }

    enum Bar {
        static let height: CGFloat = 3
    }

    enum Card {
        /// The working card's two rows without the card's insets: a text line, a gap and a 28 pt button row.
        static let workingHeight: CGFloat = 52
    }
}
