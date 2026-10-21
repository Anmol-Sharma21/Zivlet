import ZivletTrigger

/// Stored modifier names. A binding in Settings is exactly one of the four keys (03b §8.1); combinations stay
/// possible in `TriggerBindings` for later phases but are not offered or stored here.
enum ModifierName: String, Codable, CaseIterable {
    case shift, command, control, option

    var mask: ModifierMask {
        switch self {
        case .shift: .shift
        case .command: .command
        case .control: .control
        case .option: .option
        }
    }

    init?(mask: ModifierMask) {
        guard let name = Self.allCases.first(where: { $0.mask == mask }) else { return nil }
        self = name
    }
}

/// `{"convert":"shift","tools":"command","actions":"control"}`.
struct StoredBindings: Codable, Equatable {
    let convert: ModifierName
    let tools: ModifierName
    let actions: ModifierName
}

extension TriggerGroup: Codable {
    private enum CodingKeys: String, CodingKey {
        case bindings, retapClosesWheel, honorsModifierHeldAtDragStart, paused
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decode(StoredBindings.self, forKey: .bindings)
        do {
            bindings = try TriggerBindings(
                convert: stored.convert.mask, tools: stored.tools.mask, actions: stored.actions.mask)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .bindings, in: container, debugDescription: "Bindings are not three distinct modifiers")
        }
        retapClosesWheel = try container.decode(Bool.self, forKey: .retapClosesWheel)
        honorsModifierHeldAtDragStart = try container.decode(Bool.self, forKey: .honorsModifierHeldAtDragStart)
        paused = try container.decode(Bool.self, forKey: .paused)
    }

    public func encode(to encoder: any Encoder) throws {
        guard let stored = SettingsValidation.storedBindings(bindings) else {
            throw EncodingError.invalidValue(
                bindings, .init(codingPath: encoder.codingPath, debugDescription: "Bindings must be single modifiers"))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stored, forKey: .bindings)
        try container.encode(retapClosesWheel, forKey: .retapClosesWheel)
        try container.encode(honorsModifierHeldAtDragStart, forKey: .honorsModifierHeldAtDragStart)
        try container.encode(paused, forKey: .paused)
    }
}

extension TriggerGroup {
    /// The trigger machine's configuration for this group; timing numbers keep their defaults (03a §1.5).
    public var config: TriggerConfig {
        TriggerConfig(
            bindings: bindings, honorsModifierHeldAtDragStart: honorsModifierHeldAtDragStart,
            retapClosesWheel: retapClosesWheel)
    }
}
