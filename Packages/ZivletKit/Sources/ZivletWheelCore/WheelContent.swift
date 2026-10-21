import ZivletCore

public enum SelectionItemKind: String, Sendable, Codable { case file, folder, package }

/// One dragged item as seen by the slice builder. `format == nil` = unknown type.
public struct SelectionItem: Sendable, Equatable, Codable {
    public let format: FormatID?
    public let kind: SelectionItemKind
    public let isLocal: Bool
    public init(_ format: FormatID?, kind: SelectionItemKind = .file, isLocal: Bool = true) {
        self.format = format
        self.kind = kind
        self.isLocal = isLocal
    }
}

public enum SliceTarget: Sendable, Hashable, Codable {
    case convert(FormatID), tool(ToolID), action(ActionID)
}

public struct WheelSlice: Sendable, Equatable, Identifiable {
    public let id: String  // stable per mode → glass morph identity
    public let label: String
    public let symbolName: String?
    public let target: SliceTarget
    public let badge: String?  // "1 of 3" for mixed-family conversions

    public init(id: String, label: String, symbolName: String?, target: SliceTarget, badge: String?) {
        self.id = id
        self.label = label
        self.symbolName = symbolName
        self.target = target
        self.badge = badge
    }
}

/// Empty-state copy is Zivlet's own (03a §2.6, 01-prd §5.10).
public enum EmptyReason: Sendable, Equatable {
    case noItems, inaccessible, onlyLocalItems, foldersCannotConvert, unsupportedFile
    case noCommonFormat, noInstalledConverter(FormatID), noTools(FormatID?)

    /// The pill copy; format labels come from the caller's registry (`SliceBuilder.message(for:)`).
    public func message(using registry: FormatRegistry) -> String {
        func label(_ format: FormatID) -> String { registry.format(format).wheelLabel }
        switch self {
        case .noItems: return "Nothing to work on yet"
        case .inaccessible: return "Zivlet can't read one of these files"
        case .onlyLocalItems: return "Actions work on items stored on this Mac"
        case .foldersCannotConvert: return "Folders work with Actions only"
        case .unsupportedFile: return "Zivlet doesn't know this file type"
        case .noCommonFormat: return "These files can't share a format"
        case .noInstalledConverter(let f): return "\(label(f)) needs an engine that isn't installed"
        case .noTools(let f?): return "No tools for \(label(f)) files"
        case .noTools(nil): return "No tools for these items"
        }
    }
}

public enum WheelContent: Sendable, Equatable {
    case slices([WheelSlice])
    case empty(EmptyReason)

    public var slices: [WheelSlice] {
        if case .slices(let s) = self { return s }
        return []
    }
}

/// Minimal capability gate (03a §3.5): targets whose engine is missing are hidden.
public struct CapabilitySnapshot: Sendable, Equatable, Codable {
    public static let full = CapabilitySnapshot(unavailableTargets: [])
    public let unavailableTargets: Set<FormatID>
    public init(unavailableTargets: Set<FormatID>) { self.unavailableTargets = unavailableTargets }
}
