import CoreGraphics
import ZivletNotch
import ZivletShelfCore

/// The box's sizes, computed from the tokens (19c §3, §4.1), so the panel's frame and the views agree. Pure.
public enum BoxLayout {
    /// The empty hint's area: the 28 pt symbol, a gap and one line.
    static let emptyHeight: CGFloat = 72

    public static func gridRows(_ count: Int) -> Int { (count + BoxLook.Grid.columns - 1) / BoxLook.Grid.columns }

    /// The grid or list at full length, before the panel's maximum cuts it.
    static func contentHeight(_ model: BoxViewModel) -> CGFloat {
        guard !model.items.isEmpty else { return emptyHeight }
        switch model.viewMode {
        case .grid:
            let rows = CGFloat(gridRows(model.items.count))
            return rows * BoxLook.Grid.rowHeight + max(0, rows - 1) * BoxLook.Grid.gap
        case .list:
            return CGFloat(model.items.count) * BoxLook.List.rowHeight
        }
    }

    /// Everything of the expanded card except the grid or list.
    static var chromeHeight: CGFloat {
        2 * IslandContentLook.Spacing.l + BoxLook.Panel.headerHeight + BoxLook.Panel.barHeight
            + 2 * BoxLook.Panel.sectionGap
    }

    public static func size(of model: BoxViewModel) -> CGSize {
        switch model.presentation.base {
        case .hidden: return .zero
        case .docked:
            let width = model.presentation.acceptsDrop ? BoxLook.Tab.dropWidth : BoxLook.Tab.width
            return CGSize(width: width, height: BoxLook.Tab.height)
        case .collapsed:
            return CGSize(width: BoxLook.Panel.width, height: BoxLook.Panel.collapsedHeight)
        case .expanded:
            let natural = chromeHeight + contentHeight(model)
            let height = min(max(natural, BoxLook.Panel.minHeight), max(model.maxHeight, BoxLook.Panel.minHeight))
            return CGSize(width: BoxLook.Panel.width, height: height)
        }
    }

    /// The grid or list's visible height inside the expanded card.
    static func visibleContentHeight(_ model: BoxViewModel) -> CGFloat { size(of: model).height - chromeHeight }

    /// The grid or list is longer than the panel may grow.
    public static func scrolls(_ model: BoxViewModel) -> Bool { contentHeight(model) > visibleContentHeight(model) }
}
