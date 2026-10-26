import Foundation

// Debug builds only (plan 16 D-M5b-20); `check-release-paths.sh` refuses both flags in a Release binary.
#if DEBUG
    /// Screenshot and demo flags for the Drop Box: `-ZivletBoxPreview <state>` shows one state of the panel with
    /// made-up items (no file is read), and `-ZivletBoxDemo <folder>` adds the folder's files to a demo box kept in
    /// a store inside that folder, never the person's `boxes.json`. The island's `-ZivletIslandFinish` and
    /// `-ZivletIslandBackdrop` apply to the panel too.
    public struct BoxShotFlags: Sendable, Equatable {
        public enum State: String, Sendable, CaseIterable {
            case hidden, docked, collapsed, grid, list, selection, dropTarget, busy, attention, confirmTrash
            case confirmClear, empty, confirmEmpty, storageWarning
        }

        public enum Invalid: Error, Equatable {
            case missingValue(String)
            case unknown(String, String)
            case relativeFolder(String)

            /// Safe to log in public: it names the flag, never the value given.
            public var logDescription: String {
                switch self {
                case .missingValue(let flag): "no value for \(flag)"
                case .unknown(let flag, _): "unknown value for \(flag)"
                case .relativeFolder(let flag): "not an absolute folder for \(flag)"
                }
            }
        }

        public static let previewFlag = "-ZivletBoxPreview"
        public static let demoFlag = "-ZivletBoxDemo"

        public let preview: State?
        public let demoFolder: URL?

        public init(preview: State? = nil, demoFolder: URL? = nil) {
            self.preview = preview
            self.demoFolder = demoFolder
        }

        public static func parse(arguments: [String]) throws(Invalid) -> BoxShotFlags {
            let preview = try value(previewFlag, in: arguments).map { raw throws(Invalid) in
                guard let state = State(rawValue: raw) else { throw .unknown(previewFlag, raw) }
                return state
            }
            let folder = try value(demoFlag, in: arguments).map { raw throws(Invalid) in
                guard raw.hasPrefix("/") else { throw .relativeFolder(demoFlag) }
                return URL(filePath: raw, directoryHint: .isDirectory)
            }
            return BoxShotFlags(preview: preview, demoFolder: folder)
        }

        private static func value(_ flag: String, in arguments: [String]) throws(Invalid) -> String? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue(flag) }
            return arguments[index + 1]
        }
    }
#endif
