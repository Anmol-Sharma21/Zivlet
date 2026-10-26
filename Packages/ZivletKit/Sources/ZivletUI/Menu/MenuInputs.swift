import Foundation
import ZivletCore
import ZivletRuntime

/// A running batch as the menu shows it.
public struct MenuBatch: Sendable, Equatable {
    public let id: BatchID
    public let name: String
    public let percent: Int

    public init(id: BatchID, name: String, percent: Int) {
        self.id = id
        self.name = name
        self.percent = percent
    }

    /// The item converting now (or the first), and the batch's whole percent.
    public init(_ snapshot: BatchSnapshot) {
        let name = snapshot.current?.item.name ?? snapshot.items.first?.name ?? ""
        self.init(id: snapshot.batch, name: name, percent: Int((snapshot.fraction * 100).rounded(.down)))
    }
}

/// An undoable result as the menu shows it.
public struct MenuRecent: Sendable, Equatable {
    public let batch: BatchID
    public let title: String
    public let urls: [URL]

    public init(batch: BatchID, title: String, urls: [URL]) {
        self.batch = batch
        self.title = title
        self.urls = urls
    }

    /// "a.png", or "a.png and 2 more".
    public init(batch: BatchID, urls: [URL]) {
        let first = urls.first?.lastPathComponent ?? ""
        let title = urls.count > 1 ? "\(first) and \(urls.count - 1) more" : first
        self.init(batch: batch, title: title, urls: urls)
    }

    /// Outputs for a conversion, the items' new places for a Move, the copies for a Copy to….
    public init(_ entry: UndoEntry) {
        let urls: [URL]
        switch entry.kind {
        case .conversion: urls = entry.outputs.map(\.url)
        case .move: urls = entry.moves.map(\.moved)
        case .copy: urls = entry.copies.map(\.copy)
        }
        self.init(batch: entry.batch, urls: urls)
    }
}

/// The batches still converting, in the order they started; a finished snapshot leaves.
public struct ActiveBatches: Sendable, Equatable {
    public let snapshots: [BatchSnapshot]

    public init() { snapshots = [] }

    private init(snapshots: [BatchSnapshot]) { self.snapshots = snapshots }

    public func updating(_ snapshot: BatchSnapshot) -> ActiveBatches {
        guard !snapshot.isFinished else { return removing(snapshot.batch) }
        guard snapshots.contains(where: { $0.batch == snapshot.batch }) else {
            return ActiveBatches(snapshots: snapshots + [snapshot])
        }
        return ActiveBatches(snapshots: snapshots.map { $0.batch == snapshot.batch ? snapshot : $0 })
    }

    public func removing(_ batch: BatchID) -> ActiveBatches {
        ActiveBatches(snapshots: snapshots.filter { $0.batch != batch })
    }

    public var menuBatches: [MenuBatch] { snapshots.map(MenuBatch.init) }
}
