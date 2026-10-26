import AppKit

/// Asks the person for a destination folder; nil when they cancel.
public protocol FolderChoosing {
    func chooseFolder(for items: [MoveItem]) async -> URL?
    /// The same question in the words of Move to… or Copy to….
    func chooseFolder(for items: [MoveItem], mode: MovePlan.Mode) async -> URL?
}

extension FolderChoosing {
    /// A chooser that only knows the Move question answers both.
    public func chooseFolder(for items: [MoveItem], mode: MovePlan.Mode) async -> URL? {
        await chooseFolder(for: items)
    }
}

/// The "Move Here" folder panel (P1-45, 03b §7 row 4), "Copy Here" for Copy to…: directories only, new folders
/// allowed, above the wheel, starting in the first item's folder. A free-standing panel, never an app-modal
/// `runModal`; Cancel is silent.
public struct MovePanel: FolderChoosing {
    private let wheelLevel: NSWindow.Level

    public init(wheelLevel: NSWindow.Level = .floating) {
        self.wheelLevel = wheelLevel
    }

    public func chooseFolder(for items: [MoveItem]) async -> URL? { await chooseFolder(for: items, mode: .move) }

    public func chooseFolder(for items: [MoveItem], mode: MovePlan.Mode) async -> URL? {
        let panel = NSOpenPanel()
        Self.configure(panel, for: items, above: wheelLevel, mode: mode)
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }

    static func configure(
        _ panel: NSOpenPanel, for items: [MoveItem], above level: NSWindow.Level, mode: MovePlan.Mode = .move
    ) {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = mode == .copy ? "Copy Here" : "Move Here"
        panel.message = message(for: items, verb: mode == .copy ? "copy" : "move")
        panel.directoryURL = items.first?.url.deletingLastPathComponent()
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
    }

    private static func message(for items: [MoveItem], verb: String) -> String {
        guard items.count == 1, let item = items.first else { return "Choose where to \(verb) \(items.count) items." }
        return "Choose where to \(verb) “\(item.url.lastPathComponent)”."
    }
}
