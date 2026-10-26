/// Wheel limits the core needs to lint the catalog without depending on the wheel (P2-100, FR-27).
public enum WheelLimits {
    /// The most slices any wheel list shows.
    public static let maxSlots = 12
}

/// One default wheel list and how many of the 12 slots it takes.
public struct CatalogList: Sendable, Hashable, CustomStringConvertible {
    public let name: String
    public let count: Int

    public var isOverCap: Bool { count > WheelLimits.maxSlots }

    /// The count line for the exit log: "png single tools 7/12".
    public var description: String { "\(name) \(count)/\(WheelLimits.maxSlots)" }

    /// The lint's failure text: "png single tools 13 > 12".
    public var overCapDescription: String { "\(name) \(count) > \(WheelLimits.maxSlots)" }
}

/// Every default wheel list, by name, for the cap lint and its count lines (P2-100). Conversions do not depend on
/// the item count, so each format has one conversion list; empty lists are left out.
public struct CatalogLists: Sendable {
    public static let standard = CatalogLists(tools: .standard, conversions: .standard)

    private let tools: ToolCatalog
    private let conversions: ConversionCatalog

    public init(tools: ToolCatalog, conversions: ConversionCatalog) {
        self.tools = tools
        self.conversions = conversions
    }

    /// Tools for one and two items and the conversions of every format, then the actions.
    public var all: [CatalogList] {
        let perFormat = FormatID.allCases.flatMap { format in
            [
                CatalogList(name: "\(format.rawValue) single tools", count: tools.tools(for: [format]).count),
                CatalogList(name: "\(format.rawValue) multi tools", count: tools.tools(for: [format, format]).count),
                CatalogList(name: "\(format.rawValue) conversions", count: conversions.targets(for: format).count),
            ]
        }
        let actions = CatalogList(name: "actions", count: ActionID.allCases.count)
        return (perFormat + [actions]).filter { $0.count > 0 }
    }

    /// One count line per list, in `all` order.
    public var report: String { all.map(\.description).joined(separator: "\n") }
}
