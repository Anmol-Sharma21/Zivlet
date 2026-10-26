import Foundation
import ZivletTrigger

/// The boundary checks for stored and edited settings (03b §8.1). Each returns true for a value the app may use.
enum SettingsValidation {
    static let maxIdentifierLength = 255
    static let maxPathLength = Int(PATH_MAX)

    /// Bundle identifiers only: letters, digits, dots and hyphens.
    static func isValidTerminal(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= maxIdentifierLength
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    /// An absolute path. Whether the folder exists is checked where it is used (`JobRequestFactory` falls back to
    /// Downloads), so an unplugged drive never resets or locks the output group.
    static func isValidFolder(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.utf8.contains(0) && path.utf8.count <= maxPathLength
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
    /// Every placement is valid; an unknown stored name does not decode and falls back to `.automatic`.
    static func isValid(_ group: HUDGroup) -> Bool { HUDPlacement.allCases.contains(group.placement) }
    /// Every combination is valid; an unknown stored name does not decode and the group falls back to its default.
    static func isValid(_ group: BoxGroup) -> Bool { true }

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
