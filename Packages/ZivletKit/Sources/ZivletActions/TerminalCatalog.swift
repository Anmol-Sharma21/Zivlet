import AppKit

/// A terminal app Zivlet can open folders in.
public struct TerminalApp: Sendable, Equatable, Identifiable {
    /// The bundle identifier, which is also what Settings stores.
    public let id: String
    public let name: String
}

/// The Phase 1 terminals (03b §7 row 6). Terminal is the default and the fallback for an unknown stored id.
public enum TerminalCatalog {
    public static let standard = TerminalApp(id: "com.apple.Terminal", name: "Terminal")
    public static let all: [TerminalApp] = [
        standard,
        TerminalApp(id: "com.googlecode.iterm2", name: "iTerm2"),
        TerminalApp(id: "com.mitchellh.ghostty", name: "Ghostty"),
        TerminalApp(id: "com.github.wez.wezterm", name: "WezTerm"),
        TerminalApp(id: "dev.warp.Warp-Stable", name: "Warp"),
    ]

    public static func resolve(_ storedID: String) -> TerminalApp {
        all.first { $0.id == storedID } ?? standard
    }

    /// The terminals the workspace can find, in catalog order.
    public static func installed(_ workspace: any WorkspaceOpening) -> [TerminalApp] {
        all.filter { workspace.applicationURL(for: $0.id) != nil }
    }
}

/// The folders a terminal should open for the dropped items: a folder stays, a file or package means its parent;
/// each folder once, in drop order.
public enum TerminalTargets {
    public static func directories(for items: [MoveItem]) -> [URL] {
        var seen: Set<String> = []
        return items.compactMap { item in
            let folder = item.kind == .folder ? item.url : item.url.deletingLastPathComponent()
            let standard = folder.standardizedFileURL
            return seen.insert(standard.path).inserted ? standard : nil
        }
    }
}
