import Foundation
import ZivletTrigger

/// The boundary checks for stored and edited settings (03b §8.1). Each returns true for a value the app may use.
enum SettingsValidation {
    static let maxIdentifierLength = 255

    /// Bundle identifiers only: letters, digits, dots and hyphens.
    static func isValidTerminal(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= maxIdentifierLength
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// An absolute path to a directory that exists now.
    static func isValidFolder(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Three distinct single modifiers, or nil.
    static func storedBindings(_ bindings: TriggerBindings) -> StoredBindings? {
        guard let convert = ModifierName(mask: bindings.convert), let tools = ModifierName(mask: bindings.tools),
            let actions = ModifierName(mask: bindings.actions)
        else { return nil }
        return StoredBindings(convert: convert, tools: tools, actions: actions)
    }

    static func isValid(_ group: TriggerGroup) -> Bool { storedBindings(group.bindings) != nil }
    static func isValid(_ group: FeedbackGroup) -> Bool { true }
    static func isValid(_ group: OutputGroup) -> Bool { isValidFolder(group.fallbackFolder) }
    static func isValid(_ group: ActionsGroup) -> Bool { isValidTerminal(group.terminal) }
    static func isValid(_ group: UpdatesGroup) -> Bool { true }

    static func isValid(_ group: OnboardingGroup) -> Bool {
        (0..<OnboardingGroup.pageCount).contains(group.page)
            && (0...OnboardingGroup.practiceDrags).contains(group.practiceDragsLeft)
    }

    /// `~` and `~/…` become the home folder; everything else is unchanged.
    static func expandingTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return (path as NSString).expandingTildeInPath
    }
}
