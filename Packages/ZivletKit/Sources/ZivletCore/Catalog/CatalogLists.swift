/// Wheel limits the core needs to lint the catalog without depending on the wheel (P2-100, FR-27).
public enum WheelLimits {
    /// The most slices any wheel list shows.
    public static let maxSlots = 12
}

/// A tool list for one item or for several.
public enum ToolListKind: String, CaseIterable, Sendable { case single, multi }

/// A slot a later row will fill; the cap counts it now so the list cannot fill up first (P2-100, 05b).
/// The builder ignores it: there is nothing to draw yet.
public struct ReservedSlot: Sendable, Hashable {
    public let name: String
    public let formats: Set<FormatID>
    public let lists: Set<ToolListKind>

    public init(name: String, formats: Set<FormatID>, lists: Set<ToolListKind>) {
        self.name = name
        self.formats = formats
        self.lists = lists
    }

    /// TRANSCRIBE in the audio and video lists, single and multi (05b P2-100, 17 §8.1).
    public static let transcribe = ReservedSlot(
        name: "TRANSCRIBE", formats: [.mp3, .m4a, .wav, .flac, .mp4, .mov, .mkv], lists: [.single, .multi])
}

/// One default wheel list and how many of the 12 slots it takes, reserved slots included.
public struct CatalogList: Sendable, Hashable, CustomStringConvertible {
    public let name: String
    public let visible: Int
    public let reserved: Int

    public init(name: String, visible: Int, reserved: Int = 0) {
        self.name = name
        self.visible = visible
        self.reserved = reserved
    }

    public var count: Int { visible + reserved }
    public var isOverCap: Bool { count > WheelLimits.maxSlots }

    /// The count line for the exit log: "png single tools 7/12" or "mp4 single tools 10/12 (1 reserved)".
    public var description: String {
        let share = "\(name) \(count)/\(WheelLimits.maxSlots)"
        return reserved > 0 ? "\(share) (\(reserved) reserved)" : share
    }

    /// The lint's failure text: "png single tools 13 > 12".
    public var overCapDescription: String { "\(name) \(count) > \(WheelLimits.maxSlots)" }
}

/// Every default wheel list, by name, for the cap lint and its count lines (P2-100). Conversions do not depend on
/// the item count, so each format has one conversion list; empty lists are left out.
public struct CatalogLists: Sendable {
    public static let standard = CatalogLists(tools: .standard, conversions: .standard)

    private let tools: ToolCatalog
    private let conversions: ConversionCatalog
    private let reserved: [ReservedSlot]

    public init(tools: ToolCatalog, conversions: ConversionCatalog, reserved: [ReservedSlot] = [.transcribe]) {
        self.tools = tools
        self.conversions = conversions
        self.reserved = reserved
    }

    /// Tools for one and two items and the conversions of every format, then the actions.
    public var all: [CatalogList] {
        let perFormat = FormatID.allCases.flatMap { format in
            ToolListKind.allCases.map { toolList(format, $0) } + [
                CatalogList(name: "\(format.rawValue) conversions", visible: conversions.targets(for: format).count)
            ]
        }
        let actions = CatalogList(name: "actions", visible: ActionID.allCases.count)
        return (perFormat + [actions]).filter { $0.count > 0 }
    }

    /// One count line per list, in `all` order.
    public var report: String { all.map(\.description).joined(separator: "\n") }

    private func toolList(_ format: FormatID, _ kind: ToolListKind) -> CatalogList {
        let items = kind == .single ? [format] : [format, format]
        let held = reserved.count { $0.formats.contains(format) && $0.lists.contains(kind) }
        return CatalogList(
            name: "\(format.rawValue) \(kind.rawValue) tools", visible: tools.tools(for: items).count, reserved: held)
    }
}
