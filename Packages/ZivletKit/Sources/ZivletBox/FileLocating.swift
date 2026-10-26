import AppKit

/// Locate… (19c §4.1 Attention): asks the person where a missing item is now; nil when they cancel.
public protocol FileLocating {
    func locate(_ name: String, lastSeenIn folder: URL?) async -> URL?
}

/// An open panel for one file or folder, starting where the item was last seen when that folder still exists. A
/// free-standing panel above the box, never an app-modal `runModal`; Cancel is silent.
public struct SystemFileLocator: FileLocating {
    private let level: NSWindow.Level

    /// The box panel floats; the open panel sits one level above it.
    public init(above level: NSWindow.Level = .floating) { self.level = level }

    public func locate(_ name: String, lastSeenIn folder: URL?) async -> URL? {
        let panel = NSOpenPanel()
        Self.configure(panel, name: name, folder: folder, above: level)
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.url : nil
    }

    static func configure(_ panel: NSOpenPanel, name: String, folder: URL?, above level: NSWindow.Level) {
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = BoxCopy.title(.locate).replacingOccurrences(of: "…", with: "")
        panel.message = BoxCopy.locateMessage(name)
        if let folder, FileManager.default.fileExists(atPath: folder.path) { panel.directoryURL = folder }
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
    }
}
