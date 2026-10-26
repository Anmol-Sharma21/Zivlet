import AppKit

/// One key press as the key map sees it: a printable character or a special key, and the modifiers.
nonisolated public struct BoxKeyStroke: Sendable, Equatable {
    public enum Special: Sendable, Equatable {
        case space, delete, escape, left, right, up, down
    }

    public let chars: String
    public let special: Special?
    public let command: Bool
    public let shift: Bool
    public let option: Bool
    public let control: Bool

    public init(
        chars: String = "", special: Special? = nil, command: Bool = false, shift: Bool = false, option: Bool = false,
        control: Bool = false
    ) {
        self.chars = special == nil ? chars : ""
        self.special = special
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// From a key event's code, its characters without modifiers, and its modifier flags.
    public init(keyCode: UInt16, chars: String, flags: NSEvent.ModifierFlags) {
        let specials: [UInt16: Special] = [
            49: .space, 51: .delete, 117: .delete, 53: .escape, 123: .left, 124: .right, 125: .down, 126: .up,
        ]
        self.init(
            chars: chars, special: specials[keyCode], command: flags.contains(.command), shift: flags.contains(.shift),
            option: flags.contains(.option), control: flags.contains(.control))
    }

    public init(_ event: NSEvent) {
        self.init(keyCode: event.keyCode, chars: event.charactersIgnoringModifiers ?? "", flags: event.modifierFlags)
    }
}

/// What a key asks the box to do (17e §2.3).
nonisolated public enum BoxCommand: Sendable, Equatable {
    case selectAll, quickLook, copy, copyPaths, moveTo, copyTo, share, remove, trash, newBox, grid, list, collapse
    case move(GridSelection.Direction, extend: Bool)
    case type(String)
}

/// 17e §2.3's keyboard table, only while the panel is key. Keys it does not know go back to AppKit. Pure.
nonisolated public enum BoxKeyMap {
    public static func command(for stroke: BoxKeyStroke) -> BoxCommand? {
        if let special = stroke.special { return command(special, stroke) }
        guard !stroke.control else { return nil }
        let key = stroke.chars.lowercased()
        if stroke.command { return commandShortcut(key, stroke) }
        guard stroke.chars.count == 1, let scalar = stroke.chars.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(scalar), !stroke.option
        else { return nil }
        return .type(stroke.chars)
    }

    private static func command(_ special: BoxKeyStroke.Special, _ stroke: BoxKeyStroke) -> BoxCommand? {
        switch special {
        case .space: .quickLook
        case .delete: stroke.command ? .trash : .remove
        case .escape: .collapse
        case .left: .move(.left, extend: stroke.shift)
        case .right: .move(.right, extend: stroke.shift)
        case .up: .move(.up, extend: stroke.shift)
        case .down: .move(.down, extend: stroke.shift)
        }
    }

    private static func commandShortcut(_ key: String, _ stroke: BoxKeyStroke) -> BoxCommand? {
        switch (key, stroke.shift, stroke.option) {
        case ("a", false, false): .selectAll
        case ("c", false, false): .copy
        case ("c", false, true): .copyPaths
        case ("c", true, false): .copyTo
        case ("m", true, false): .moveTo
        case ("s", false, false): .share
        case ("n", false, false): .newBox
        case ("1", false, false): .grid
        case ("2", false, false): .list
        case ("w", false, false): .collapse
        default: nil
        }
    }
}
