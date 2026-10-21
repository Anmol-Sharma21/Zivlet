import Foundation
import ZivletCore

/// Where the media tools came from. `override` and `development` exist only for local development.
public enum ToolOrigin: String, Sendable, Codable {
    case bundled, override, development
}

/// `ffmpeg` and `ffprobe` from one directory.
public struct MediaTools: Sendable, Equatable {
    public let directory: URL
    public let origin: ToolOrigin

    public init(directory: URL, origin: ToolOrigin) {
        self.directory = directory
        self.origin = origin
    }

    public var ffmpeg: URL { directory.appending(path: "ffmpeg", directoryHint: .notDirectory) }
    public var ffprobe: URL { directory.appending(path: "ffprobe", directoryHint: .notDirectory) }
}

/// Finds the media tools (P1-21, 10 §8.9): the app's `Contents/Helpers` first; then, in Debug builds only, the
/// directory named by `ZIVLET_FFMPEG_DIR` and Homebrew's `/opt/homebrew/bin` and `/usr/local/bin`. Release builds
/// trust only their own signed helpers (index D-M3-19): no Homebrew path is compiled in, and the environment is not
/// read, so a launch environment cannot make the app run another binary with its file-access grants. A directory
/// counts only when it holds both tools.
public struct EngineLocator: Sendable {
    public static let overrideVariable = "ZIVLET_FFMPEG_DIR"

    public static var honoursOverride: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    public static var defaultDevelopmentDirectories: [URL] {
        #if DEBUG
            [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")]
        #else
            []
        #endif
    }

    let bundledHelpers: URL?
    let environment: [String: String]
    let developmentDirectories: [URL]
    let isExecutable: @Sendable (String) -> Bool

    public init(
        bundledHelpers: URL? = Bundle.main.bundleURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        developmentDirectories: [URL] = EngineLocator.defaultDevelopmentDirectories,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.bundledHelpers = bundledHelpers
        self.environment = environment
        self.developmentDirectories = developmentDirectories
        self.isExecutable = isExecutable
    }

    public func locateMediaTools() throws(JobError) -> MediaTools {
        let candidates =
            [bundledHelpers.map { MediaTools(directory: $0, origin: .bundled) }, override]
            + developmentDirectories.map { MediaTools(directory: $0, origin: .development) }
        guard let found = candidates.compactMap({ $0 }).first(where: hasBothTools) else {
            throw .engineMissing(.media)
        }
        return found
    }

    /// The override directory when it is a safe absolute path in a Debug build; anything else is ignored.
    private var override: MediaTools? {
        guard Self.honoursOverride, let path = environment[Self.overrideVariable], path.hasPrefix("/"),
            !path.split(separator: "/").contains("..")
        else { return nil }
        return MediaTools(directory: URL(fileURLWithPath: path, isDirectory: true), origin: .override)
    }

    private func hasBothTools(_ tools: MediaTools) -> Bool {
        isExecutable(tools.ffmpeg.path) && isExecutable(tools.ffprobe.path)
    }
}
