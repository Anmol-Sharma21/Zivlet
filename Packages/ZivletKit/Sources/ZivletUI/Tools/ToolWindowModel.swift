import Foundation

/// Why a tool's Apply button is off, in Zivlet's own words (P2-30 "disabled-state reasons"). It is never empty: the
/// initializer fails on text that is only white space, so an Apply cannot be off without a reason.
public struct DisabledReason: Sendable, Equatable {
    public let text: String

    public init?(_ text: String) {
        guard !text.allSatisfy(\.isWhitespace) else { return nil }
        self.text = text
    }
}

/// The tool window's Apply button: on with its label (each tool names its own, "Lock"), or off with the reason shown
/// under it and read by VoiceOver.
public enum ApplyState: Sendable, Equatable {
    case enabled(label: String)
    case disabled(label: String, reason: DisabledReason)

    public var label: String {
        switch self {
        case .enabled(let label), .disabled(let label, _): label
        }
    }

    public var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    public var reason: String? {
        if case .disabled(_, let reason) = self { return reason.text }
        return nil
    }
}

/// The shell's state (P2-30, plan 20b A1): the tool's symbol and name, the file line, Apply, the word on the button
/// that closes without applying ("Cancel", or "Close" for a results window) and whether the tool is working. A value:
/// every edit returns a new one.
public struct ToolWindowModel: Sendable, Equatable {
    public let symbol: String
    public let title: String
    public let fileLine: String
    public let apply: ApplyState
    public let cancelLabel: String
    public let isBusy: Bool

    public init(
        symbol: String, title: String, fileLine: String, apply: ApplyState, cancelLabel: String = "Cancel",
        isBusy: Bool = false
    ) {
        self.symbol = symbol
        self.title = title
        self.fileLine = fileLine
        self.apply = apply
        self.cancelLabel = cancelLabel
        self.isBusy = isBusy
    }

    public func with(apply: ApplyState) -> ToolWindowModel {
        ToolWindowModel(
            symbol: symbol, title: title, fileLine: fileLine, apply: apply, cancelLabel: cancelLabel, isBusy: isBusy)
    }

    public func busy(_ isBusy: Bool = true) -> ToolWindowModel {
        ToolWindowModel(
            symbol: symbol, title: title, fileLine: fileLine, apply: apply, cancelLabel: cancelLabel, isBusy: isBusy)
    }

    /// Apply is on and the tool is not already working.
    public var canApply: Bool { apply.isEnabled && !isBusy }

    /// "Report.pdf" for one file, "3 files" for more (the text card's naming), nothing for none.
    public static func fileLine(names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: "\(names.count) files"
        }
    }
}
