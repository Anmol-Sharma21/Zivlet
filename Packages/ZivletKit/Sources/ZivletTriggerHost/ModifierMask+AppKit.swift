import AppKit
import ZivletTrigger

extension ModifierMask {
    /// Keeps ⌃⌥⇧⌘ only; Caps Lock, Fn and numeric-pad bits are dropped (03a §1.2).
    public init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, ModifierMask)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        let raw = pairs.reduce(UInt8(0)) { bits, pair in flags.contains(pair.0) ? bits | pair.1.rawValue : bits }
        self.init(rawValue: raw)
    }
}
