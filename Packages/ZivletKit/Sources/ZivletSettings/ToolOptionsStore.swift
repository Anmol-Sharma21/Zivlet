import Foundation
import ZivletCore
import os

/// A tool's remembered options (P2-30 "options remembered per tool", plan 20b A4): a plain value that is `Codable`.
/// A password is held only by `JobSecret`, which is not `Codable`, so an options struct holding one does not compile
/// as remembered options and a password cannot be stored by accident (P2-102).
public protocol RememberedToolOptions: Codable, Sendable, Equatable {
    /// What a tool starts with before anything was saved, and after a stored value turns out unreadable.
    static var defaults: Self { get }
}

/// Each tool's options as JSON in `UserDefaults` under `tools.<toolID>.options`, nothing else. An unreadable value
/// gives the tool's defaults, with one error line naming the tool (never the value).
@MainActor
public final class ToolOptionsStore {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "settings")
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func key(for tool: ToolID) -> String { "tools.\(tool.rawValue).options" }

    public func load<Options: RememberedToolOptions>(_ type: Options.Type, for tool: ToolID) -> Options {
        guard let stored = defaults.object(forKey: Self.key(for: tool)) else { return .defaults }
        guard let data = stored as? Data, let options = try? JSONDecoder().decode(Options.self, from: data) else {
            Self.logger.error("Tool options unreadable, defaults used: \(tool.rawValue, privacy: .public)")
            return .defaults
        }
        return options
    }

    public func save<Options: RememberedToolOptions>(_ options: Options, for tool: ToolID) {
        do {
            defaults.set(try JSONEncoder().encode(options), forKey: Self.key(for: tool))
        } catch {
            Self.logger.error("Tool options not saved: \(tool.rawValue, privacy: .public)")
        }
    }
}
