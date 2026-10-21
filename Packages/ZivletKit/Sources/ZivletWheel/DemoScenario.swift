import Foundation
import ZivletCore
import ZivletWheelCore

// Debug builds only: Release must not ship a way to show the wheel or fabricate a payload without a drag.
#if DEBUG
    public enum DemoScenarioError: Error, Equatable, Sendable {
        case unknownMode(String)
        case missingValue(String)
        case badHighlight(String)
        case badRepeat(String)
    }

    /// DEBUG launch arguments that show the wheel at screen centre without a drag, so screenshots can be automated:
    /// `-ZivletDemoWheel convert|tools|actions [-ZivletDemoFiles a.png,Photos/] [-ZivletDemoHighlight 2]
    /// [-ZivletDemoRepeat 50]`. File names need not exist; a trailing "/" makes a folder. The repeat count (1…1000)
    /// shows and hides the wheel that many times, for the bench's trigger→frame timing (P1-63).
    public struct DemoScenario: Sendable, Equatable {
        public static let wheelFlag = "-ZivletDemoWheel"
        public static let filesFlag = "-ZivletDemoFiles"
        public static let highlightFlag = "-ZivletDemoHighlight"
        public static let repeatFlag = "-ZivletDemoRepeat"
        static let maxRepeats = 1_000
        static let sampleBytes: Int64 = 2_400_000

        public let mode: WheelMode
        public let payload: DragPayload
        public let highlight: Int?
        public let repeats: Int

        /// Nil when the wheel flag is absent.
        public static func parse(
            arguments: [String], registry: FormatRegistry = .standard
        ) throws(DemoScenarioError) -> DemoScenario? {
            guard let rawMode = try value(after: wheelFlag, in: arguments) else { return nil }
            guard let mode = WheelMode(rawValue: rawMode) else { throw .unknownMode(rawMode) }
            let names = try value(after: filesFlag, in: arguments)?.split(separator: ",").map(String.init)
            let highlight = try value(after: highlightFlag, in: arguments).map { raw throws(DemoScenarioError) in
                guard let index = Int(raw), index >= 0 else { throw .badHighlight(raw) }
                return index
            }
            let repeats = try value(after: repeatFlag, in: arguments).map { raw throws(DemoScenarioError) in
                guard let count = Int(raw), (1...maxRepeats).contains(count) else { throw .badRepeat(raw) }
                return count
            }
            let payload = makePayload(names ?? sampleNames(mode), registry: registry)
            return DemoScenario(mode: mode, payload: payload, highlight: highlight, repeats: repeats ?? 1)
        }

        /// The default sample selection for a mode (status-menu demo items).
        public static func sample(_ mode: WheelMode, registry: FormatRegistry = .standard) -> DemoScenario {
            DemoScenario(
                mode: mode, payload: makePayload(sampleNames(mode), registry: registry), highlight: nil, repeats: 1)
        }

        static func sampleNames(_ mode: WheelMode) -> [String] {
            switch mode {
            case .convert: ["Sunset.heic"]
            case .tools: ["Interview.mov"]
            case .actions: ["Report.pdf", "Photos/"]
            }
        }

        private static func value(after flag: String, in arguments: [String]) throws(DemoScenarioError) -> String? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue(flag) }
            return arguments[index + 1]
        }

        private static func makePayload(_ names: [String], registry: FormatRegistry) -> DragPayload {
            let folder = URL(fileURLWithPath: "/tmp/ZivletDemo", isDirectory: true)
            let entries = names.map { raw in
                let isFolder = raw.hasSuffix("/")
                let name = isFolder ? String(raw.dropLast()) : raw
                let format = isFolder ? nil : registry.formatID(fileName: name)
                let kind: SelectionItemKind = isFolder ? .folder : .file
                return (
                    url: folder.appending(path: name, directoryHint: isFolder ? .isDirectory : .notDirectory),
                    item: SelectionItem(format, kind: kind),
                    hub: HubItem(name: name, format: format, kind: kind, byteCount: isFolder ? nil : sampleBytes)
                )
            }
            return DragPayload(
                changeCount: -1, urls: entries.map(\.url), items: entries.map(\.item), hubItems: entries.map(\.hub))
        }
    }
#endif
