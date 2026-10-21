import AppKit

/// The two `NSWorkspace` calls the Terminal action needs, so tests launch nothing.
public protocol WorkspaceOpening {
    func applicationURL(for bundleID: String) -> URL?
    func open(_ urls: [URL], withApplicationAt app: URL) async throws
}

/// `NSWorkspace.shared` behind `WorkspaceOpening`.
public struct SystemWorkspace: WorkspaceOpening {
    public init() {}

    public func applicationURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public func open(_ urls: [URL], withApplicationAt app: URL) async throws {
        _ = try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: .init())
    }
}

/// Open in Terminal (P1-45, 03b §7 row 6): the folders for the items, in the terminal chosen in Settings.
public struct TerminalAction {
    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening = SystemWorkspace()) {
        self.workspace = workspace
    }

    public func open(_ items: [MoveItem], terminalID: String) async -> ActionOutcome {
        let terminal = TerminalCatalog.resolve(terminalID)
        guard let app = workspace.applicationURL(for: terminal.id) else {
            return .failed(.terminalMissing(terminal.name))
        }
        do {
            try await workspace.open(TerminalTargets.directories(for: items), withApplicationAt: app)
        } catch {
            return .failed(.terminalFailed(terminal.name, code: (error as NSError).code))
        }
        return .done(toast: "Opened in \(terminal.name)")
    }
}
