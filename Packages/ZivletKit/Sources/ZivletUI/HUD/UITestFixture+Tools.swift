import Foundation
import ZivletCore

// Debug builds only: the tools mode of the owner-run UI test (plan 20b A6, D-M7-12).
#if DEBUG
    /// What `-UITestFixture <dir>` shows: the result card (`convert`, also when no mode is given) or a tool run on
    /// the folder's files (`tools`).
    public enum UITestMode: String, Sendable {
        case convert, tools
    }

    public enum UITestFixtureError: Error, Equatable {
        case missingValue(String)
        case unknownMode(String)
        case unknownTool(String)
        case noFiles
    }

    /// `-UITestFixture <dir> -UITestMode tools -UITestTool <toolID>` runs the tool on the visible files in `<dir>`
    /// through the drop path, as if they had been dropped on its slice, so an XCUITest can drive the tool window
    /// without a cross-app drag. The wheel has no keyboard selection to drive, so the tool is named instead.
    extension UITestFixture {
        public static let modeFlag = "-UITestMode"
        public static let toolFlag = "-UITestTool"

        /// Nil when the flag is absent; an unknown mode is refused.
        public static func mode(arguments: [String]) throws(UITestFixtureError) -> UITestMode? {
            guard let raw = try value(after: modeFlag, in: arguments) else { return nil }
            guard let mode = UITestMode(rawValue: raw) else { throw .unknownMode(raw) }
            return mode
        }

        /// Nil when the flag is absent; a name that is not a tool is refused.
        public static func tool(arguments: [String]) throws(UITestFixtureError) -> ToolID? {
            guard let raw = try value(after: toolFlag, in: arguments) else { return nil }
            guard let tool = ToolID(rawValue: raw) else { throw .unknownTool(raw) }
            return tool
        }

        /// The folder's regular files that are not hidden, by name; none is refused.
        public static func files(in dir: URL) throws -> [URL] {
            let keys: [URLResourceKey] = [.isRegularFileKey]
            let found = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            let files = found.filter { (try? $0.resourceValues(forKeys: Set(keys)))?.isRegularFile == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { throw UITestFixtureError.noFiles }
            return files
        }

        private static func value(after flag: String, in arguments: [String]) throws(UITestFixtureError) -> String? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue(flag) }
            return arguments[index + 1]
        }
    }
#endif
