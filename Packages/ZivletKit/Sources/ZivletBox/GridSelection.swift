import Foundation
import ZivletCore

/// Which items are selected (17e §2.3): click, ⇧-click for a range from the anchor, ⌘-click to toggle, arrows by
/// one item or one row, ⌘A, and the marquee. Pure; the order of the box's items is passed in.
nonisolated public struct GridSelection: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case left, right, up, down
    }

    public let selected: Set<UUID>
    /// Where a range starts.
    public let anchor: UUID?
    /// Where the arrows move from.
    public let focus: UUID?

    public init(selected: Set<UUID> = [], anchor: UUID? = nil, focus: UUID? = nil) {
        self.selected = selected
        self.anchor = anchor
        self.focus = focus
    }

    public func clicking(_ id: UUID, extend: Bool, toggle: Bool, in order: [UUID]) -> GridSelection {
        if toggle {
            return GridSelection(selected: selected.symmetricDifference([id]), anchor: id, focus: id)
        }
        if extend, let anchor {
            return GridSelection(selected: Self.range(anchor, id, in: order), anchor: anchor, focus: id)
        }
        return GridSelection(selected: [id], anchor: id, focus: id)
    }

    public func moving(_ direction: Direction, extend: Bool, in order: [UUID], columns: Int) -> GridSelection {
        guard let first = order.first else { return GridSelection() }
        guard let from = focus.flatMap({ order.firstIndex(of: $0) }) else {
            return GridSelection(selected: [first], anchor: first, focus: first)
        }
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -max(1, columns)
        case .down: step = max(1, columns)
        }
        let target = from + step
        let next = order[order.indices.contains(target) ? target : from]
        guard extend, let anchor else { return GridSelection(selected: [next], anchor: next, focus: next) }
        return GridSelection(selected: Self.range(anchor, next, in: order), anchor: anchor, focus: next)
    }

    public func all(_ order: [UUID]) -> GridSelection {
        GridSelection(selected: Set(order), anchor: order.first, focus: order.last)
    }

    public func cleared() -> GridSelection { GridSelection() }

    /// Only the ids still in the box.
    public func keeping(_ order: [UUID]) -> GridSelection {
        let ids = Set(order)
        return GridSelection(
            selected: selected.intersection(ids), anchor: anchor.flatMap { ids.contains($0) ? $0 : nil },
            focus: focus.flatMap { ids.contains($0) ? $0 : nil })
    }

    /// The cells' frames in the grid's own space (origin top-left, y down), by index.
    public static func cellFrames(count: Int, columns: Int, cell: Double, rowHeight: Double, gap: Double) -> [Rect2D] {
        (0..<max(0, count)).map { n in
            Rect2D(
                x: Double(n % columns) * (cell + gap), y: Double(n / columns) * (rowHeight + gap), width: cell,
                height: rowHeight)
        }
    }

    /// The indexes of the cells the marquee touches.
    public static func marquee(_ rect: Rect2D, cells: [Rect2D]) -> [Int] {
        cells.indices.filter { n in
            let c = cells[n]
            return c.minX < rect.maxX && rect.minX < c.maxX && c.minY < rect.maxY && rect.minY < c.maxY
        }
    }

    private static func range(_ a: UUID, _ b: UUID, in order: [UUID]) -> Set<UUID> {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return [b] }
        return Set(order[min(i, j)...max(i, j)])
    }
}

/// Type to select (17e §2.3): letters typed within 0.8 s of each other build one prefix; the first item whose name
/// starts with it, ignoring case, is selected. The time comes from the caller, so tests use a manual clock.
nonisolated public struct TypeSelect: Sendable, Equatable {
    public static let reset = 0.8

    public let prefix: String
    public let lastAt: Double?

    public init(prefix: String = "", lastAt: Double? = nil) {
        self.prefix = prefix
        self.lastAt = lastAt
    }

    public func typing(_ characters: String, at time: Double) -> TypeSelect {
        let continues = lastAt.map { time - $0 <= Self.reset } ?? false
        return TypeSelect(prefix: (continues ? prefix : "") + characters, lastAt: time)
    }

    public func match(in names: [(UUID, String)]) -> UUID? {
        guard !prefix.isEmpty else { return nil }
        return names.first { $0.1.lowercased().hasPrefix(prefix.lowercased()) }?.0
    }
}
