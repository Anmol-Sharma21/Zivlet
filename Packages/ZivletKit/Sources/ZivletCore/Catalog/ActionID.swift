/// The six actions in fixed wheel order (03a §2.6). Symbol names are Zivlet's own choice.
public enum ActionID: String, CaseIterable, Codable, Sendable {
    case shareAirDrop, pinFloating, copyTo, moveTo, copyFilePath, openInTerminal

    public var wheelLabel: String {
        switch self {
        case .shareAirDrop: "AIRDROP"
        case .pinFloating: "FLOAT"
        case .copyTo: "COPY"
        case .moveTo: "MOVE"
        case .copyFilePath: "COPY PATH"
        case .openInTerminal: "TERMINAL"
        }
    }

    public var symbolName: String {
        switch self {
        case .shareAirDrop: "airplayaudio"
        case .pinFloating: "pin"
        case .copyTo: "plus.square.on.square"
        case .moveTo: "arrow.right.doc.on.clipboard"
        case .copyFilePath: "link"
        case .openInTerminal: "apple.terminal"
        }
    }
}
