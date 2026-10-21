import ZivletCore

/// Why an action could not run, in Zivlet's own words (03b §7 "Errors").
public enum ActionError: Error, Sendable, Equatable {
    /// None of the dropped items is a file or folder on this Mac.
    case nothingLocal(ActionID)
    /// The pasteboard did not take the items or the text.
    case clipboardRefused

    /// One sentence for the result card.
    public var userMessage: String {
        switch self {
        case .nothingLocal(let action): Self.nothingLocalMessage(action)
        case .clipboardRefused: "Zivlet couldn't write to the clipboard. Try again."
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
