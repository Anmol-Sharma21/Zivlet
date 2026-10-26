/// The six actions in fixed wheel order (03a §2.6). Symbol names are Zivlet's own choice. `pinFloating` keeps its
/// raw value (stored in settings and undo files) though its slice is now the Drop Box's BOX (P2-55 §9.5).
public enum ActionID: String, CaseIterable, Codable, Sendable {
    case shareAirDrop, pinFloating, copyTo, moveTo, copyFilePath, openInTerminal

    public var wheelLabel: String {
        switch self {
        case .shareAirDrop: "AIRDROP"
        case .pinFloating: "BOX"
        case .copyTo: "COPY"
        case .moveTo: "MOVE"
        case .copyFilePath: "COPY PATH"
        case .openInTerminal: "TERMINAL"
        }
    }

    public var symbolName: String {
        switch self {
        case .shareAirDrop: "airplayaudio"
        case .pinFloating: "tray.full"
        case .copyTo: "plus.square.on.square"
        case .moveTo: "arrow.right.doc.on.clipboard"
        case .copyFilePath: "link"
        case .openInTerminal: "apple.terminal"
        }
    }
}
