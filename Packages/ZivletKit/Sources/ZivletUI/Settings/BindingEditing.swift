import ZivletCore
import ZivletTrigger

extension TriggerBindings {
    /// The modifier that opens `mode`'s wheel.
    public func modifier(for mode: WheelMode) -> ModifierMask {
        switch mode {
        case .convert: convert
        case .tools: tools
        case .actions: actions
        }
    }
}

/// One entry of a wheel-key picker.
public struct ModifierChoice: Sendable, Equatable, Identifiable {
    public let mask: ModifierMask
    public let title: String
    public var id: UInt8 { mask.rawValue }
}

/// The wheel-key pickers' rule (03b §8.1): the three wheels always have three different keys, so choosing a key
/// another wheel uses swaps the two.
public enum BindingEditing {
    public static let choices = [
        ModifierChoice(mask: .shift, title: "⇧ Shift"), ModifierChoice(mask: .command, title: "⌘ Command"),
        ModifierChoice(mask: .control, title: "⌃ Control"), ModifierChoice(mask: .option, title: "⌥ Option"),
    ]

    public static func set(_ modifier: ModifierMask, for mode: WheelMode, in bindings: TriggerBindings)
        -> TriggerBindings
    {
        let old = bindings.modifier(for: mode)
        let masks = WheelMode.allCases.map { other -> ModifierMask in
            if other == mode { return modifier }
            return bindings.modifier(for: other) == modifier ? old : bindings.modifier(for: other)
        }
        return (try? TriggerBindings(convert: masks[0], tools: masks[1], actions: masks[2])) ?? bindings
    }
}
