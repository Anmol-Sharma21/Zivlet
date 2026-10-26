import Foundation

/// The volume an item lives on (`st_dev`); a move between volumes is a copy, a check and a trash.
nonisolated public struct VolumeID: Sendable, Hashable {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
}

/// One dragged item, or the chosen destination, with what it is on disk.
nonisolated public struct MoveItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case file, folder, package }

    public let url: URL
    public let kind: Kind

    public init(url: URL, kind: Kind) {
        self.url = url
        self.kind = kind
    }
}

nonisolated public struct MoveStep: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Same volume: one exclusive rename.
        case rename
        /// Another volume: copy under a hidden name, verify, rename, then trash the original.
        case copyThenTrash
        /// Copy to… (D-M5b-13): copy under a hidden name, verify, rename; the original stays where it is.
        case copy
    }

    public let source: URL
    public let target: URL
    public let kind: Kind
    public let itemKind: MoveItem.Kind
}

nonisolated public enum MoveSkip: Sendable, Equatable {
    /// The item is already directly inside the destination.
    case alreadyThere(URL)
}

/// Why nothing is moved.
nonisolated public enum MoveRefusal: Error, Sendable, Equatable {
    case notAFolder
    case intoItself(URL)
    case noFreeName(URL)

    public var userMessage: String {
        switch self {
        case .notAFolder: "Choose a folder on this Mac to move into."
        case .intoItself(let url): "“\(url.lastPathComponent)” can't be moved into itself."
        case .noFreeName(let url): "Every name for “\(url.lastPathComponent)” is already taken in that folder."
        }
    }
}

nonisolated public struct MovePlan: Sendable, Equatable {
    /// Move to… puts items elsewhere; Copy to… leaves them and makes copies (D-M5b-13).
    public enum Mode: Sendable, Equatable { case move, copy }

    public let destination: URL
    public let steps: [MoveStep]
    public let skipped: [MoveSkip]
    public let mode: Mode

    public init(destination: URL, steps: [MoveStep], skipped: [MoveSkip], mode: Mode = .move) {
        self.destination = destination
        self.steps = steps
        self.skipped = skipped
        self.mode = mode
    }
}

/// Pure Move planning (P1-45, 03b §7 row 4). `volumes` answers the volume of a path; `existing` holds the paths
/// already in the destination. Targets never collide with `existing` or with each other. In copy mode every item is
/// copied, an item already in the destination too (its copy takes the next free name).
nonisolated public enum MovePlanner {
    public static func plan(
        items: [MoveItem], destination: MoveItem, volumes: (URL) -> VolumeID?, existing: Set<String>,
        mode: MovePlan.Mode = .move
    ) throws(MoveRefusal) -> MovePlan {
        guard destination.kind == .folder else { throw .notAFolder }
        let folder = destination.url.standardizedFileURL
        if let parent = items.first(where: { contains($0, folder) }) { throw .intoItself(parent.url) }
        var taken = Set(existing.map(MoveNames.key))
        var steps: [MoveStep] = []
        var skipped: [MoveSkip] = []
        let destinationVolume = volumes(folder)
        for item in items {
            let source = item.url.standardizedFileURL
            if mode == .move, source.deletingLastPathComponent().path == folder.path {
                skipped.append(.alreadyThere(item.url))
                continue
            }
            let target = try freeTarget(for: item, in: folder, taken: taken)
            taken.insert(MoveNames.key(target.path))
            let sameVolume = destinationVolume != nil && volumes(source) == destinationVolume
            let kind: MoveStep.Kind = mode == .copy ? .copy : (sameVolume ? .rename : .copyThenTrash)
            steps.append(MoveStep(source: source, target: target, kind: kind, itemKind: item.kind))
        }
        return MovePlan(destination: folder, steps: steps, skipped: skipped, mode: mode)
    }

    /// A folder or package contains `folder` when it is `folder` or one of its ancestors.
    private static func contains(_ item: MoveItem, _ folder: URL) -> Bool {
        guard item.kind != .file else { return false }
        let path = item.url.standardizedFileURL.path
        return folder.path == path || folder.path.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }

    private static func freeTarget(for item: MoveItem, in folder: URL, taken: Set<String>) throws(MoveRefusal)
        -> URL
    {
        let name = item.url.lastPathComponent
        for counter in 1...MoveNames.maxCandidates {
            let target = folder.appending(
                path: MoveNames.candidate(name, counter: counter, kind: item.kind), directoryHint: .notDirectory)
            if !taken.contains(MoveNames.key(target.path)) { return target }
        }
        throw .noFreeName(item.url)
    }
}
