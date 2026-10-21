import ZivletCore

/// Why an action could not run, in Zivlet's own words (03b §7 "Errors").
public enum ActionError: Error, Sendable, Equatable {
    /// None of the dropped items is a file or folder on this Mac.
    case nothingLocal(ActionID)
    /// The pasteboard did not take the items or the text.
    case clipboardRefused
    /// AirDrop is off, missing on this Mac, or cannot take these items.
    case airDropUnavailable
    /// The AirDrop sheet reported an error other than the person cancelling.
    case airDropFailed(code: Int)
    /// Float waits for the shelf (P2-55); its petal is hidden, so this only answers a stray request.
    case floatNotYetAvailable
    /// The terminal chosen in Settings (named) is not on this Mac.
    case terminalMissing(String)
    /// The terminal (named) did not open the folders.
    case terminalFailed(String, code: Int)

    /// One sentence for the result card.
    public var userMessage: String {
        switch self {
        case .nothingLocal(let action): Self.nothingLocalMessage(action)
        case .clipboardRefused: "Zivlet couldn't write to the clipboard. Try again."
        case .airDropUnavailable, .airDropFailed: "Zivlet couldn't start AirDrop for these files."
        case .floatNotYetAvailable: "Float arrives in a later version."
        case .terminalMissing(let name): "\(name) isn't installed. Choose another in Settings."
        case .terminalFailed(let name, _): "Zivlet couldn't open \(name)."
        }
    }

    /// The text behind "Show details", when there is more to say than `userMessage`.
    public var detail: String? {
        switch self {
        case .airDropFailed(let code): "AirDrop reported error \(code)."
        case .terminalFailed(_, let code): "The system reported error \(code)."
        default: nil
        }
    }

    private static func nothingLocalMessage(_ action: ActionID) -> String {
        switch action {
        case .copyTo: "Copy works only with items stored on this Mac."
        case .copyFilePath: "Paths can be copied only for items stored on this Mac."
        case .shareAirDrop: "Zivlet couldn't start AirDrop for these files."
        case .moveTo: "Only items stored on this Mac can be moved."
        case .openInTerminal: "Only folders on this Mac can be opened in a terminal."
        case .pinFloating: "Float arrives in a later version."
        }
    }
}
