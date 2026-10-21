import ZivletCore

/// The four trigger modifiers ⌃⌥⇧⌘ as a 4-bit set (03a §1.7). Other bits are dropped.
public struct ModifierMask: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue & 0b1111 }

    public static let control = ModifierMask(rawValue: 1 << 0)
    public static let option = ModifierMask(rawValue: 1 << 1)
    public static let shift = ModifierMask(rawValue: 1 << 2)
    public static let command = ModifierMask(rawValue: 1 << 3)

    /// Every non-empty combination, raw values 1…15.
    public static let allNonEmpty: [ModifierMask] = (1...15).map { ModifierMask(rawValue: UInt8($0)) }

    /// Display symbols in the fixed ⌃⌥⇧⌘ order (03a §1.7).
    public var symbols: String {
        let ordered: [(ModifierMask, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return ordered.filter { contains($0.0) }.map(\.1).joined()
    }
}

/// Why a set of bindings was refused.
public enum BindingError: Error, Equatable, Sendable {
    case emptyMask(WheelMode)
    case duplicate(ModifierMask)
}

/// Which exact modifier set opens which wheel. Validated: no empty masks, no duplicates. Decoding runs the same
/// validation and requires the encoded `schemaVersion` (03a §1.7).
public struct TriggerBindings: Sendable, Equatable, Codable {
    public static let schemaVersion = 1

    /// ⇧ Convert, ⌘ Tools, ⌃ Actions.
    public static let standard = TriggerBindings(unchecked: .shift, tools: .command, actions: .control)

    public let convert: ModifierMask
    public let tools: ModifierMask
    public let actions: ModifierMask

    public init(convert: ModifierMask, tools: ModifierMask, actions: ModifierMask) throws(BindingError) {
        let masks: [(WheelMode, ModifierMask)] = [(.convert, convert), (.tools, tools), (.actions, actions)]
        if let empty = masks.first(where: { $0.1.isEmpty }) { throw .emptyMask(empty.0) }
        if convert == tools || convert == actions { throw .duplicate(convert) }
        if tools == actions { throw .duplicate(tools) }
        self.init(unchecked: convert, tools: tools, actions: actions)
    }

    private init(unchecked convert: ModifierMask, tools: ModifierMask, actions: ModifierMask) {
        self.convert = convert
        self.tools = tools
        self.actions = actions
    }

    /// Exact equality only; a superset or subset never matches.
    public func mode(matching mask: ModifierMask) -> WheelMode? {
        switch mask {
        case tools: .tools
        case convert: .convert
        case actions: .actions
        default: nil
        }
    }

    /// "⇧: Convert · ⌘: Tools · ⌃: Actions".
    public var menuSummary: String {
        [(convert, "Convert"), (tools, "Tools"), (actions, "Actions")]
            .map { "\($0.0.symbols): \($0.1)" }
            .joined(separator: " · ")
    }
}

extension TriggerBindings {
    private enum CodingKeys: String, CodingKey { case schemaVersion, convert, tools, actions }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container, debugDescription: "Unsupported schemaVersion \(version)")
        }
        do {
            try self.init(
                convert: container.decode(ModifierMask.self, forKey: .convert),
                tools: container.decode(ModifierMask.self, forKey: .tools),
                actions: container.decode(ModifierMask.self, forKey: .actions))
        } catch let error as BindingError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid bindings", underlyingError: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(convert, forKey: .convert)
        try container.encode(tools, forKey: .tools)
        try container.encode(actions, forKey: .actions)
    }
}
