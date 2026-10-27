import AppKit
import ZivletActions
import ZivletShelfCore

@testable import ZivletBox

/// Records every share picker the box asks for: the items and where it points.
@MainActor
final class FakeSharePicker: SharePicking {
    struct Shown: Equatable {
        let urls: [URL]
        let rect: CGRect
        let edge: NSRectEdge
    }

    private(set) var shown: [Shown] = []
    var onFailure: () -> Void = {}

    func show(_ urls: [URL], relativeTo rect: CGRect, of view: NSView, edge: NSRectEdge) {
        shown.append(Shown(urls: urls, rect: rect, edge: edge))
    }
}

/// Every result the box hands to the presenters, with the anchor it gave.
@MainActor
final class ResultLog {
    private(set) var results: [ActionResult] = []
    private(set) var anchors: [CGRect?] = []

    func record(_ result: ActionResult, _ anchor: CGRect?) {
        results.append(result)
        anchors.append(anchor)
    }
}

/// AirDrop's sharing service: available or not, and the items it was asked to send.
final class FakeBoxSharing: SharingService {
    let available: Bool
    private(set) var performed: [[URL]] = []

    init(available: Bool = true) { self.available = available }

    func canPerform(_ items: [URL]) -> Bool { available && !items.isEmpty }

    func perform(_ items: [URL], completion: @escaping (SharingOutcome) -> Void) {
        performed.append(items)
        completion(.sent)
    }
}

/// The folder chooser of Move to… and Copy to…: a fixed answer (nil = cancelled), and how often it was asked.
final class FakeBoxFolders: FolderChoosing {
    var answer: URL?
    private(set) var asked = 0

    init(answer: URL?) { self.answer = answer }

    func chooseFolder(for items: [MoveItem]) async -> URL? {
        asked += 1
        return answer
    }
}

/// A Trash that records what it was given and refuses the paths in `refusing`. With `removes`, a file it takes is
/// deleted; with a `folder`, it is moved there, as into the Trash, and that place is returned; otherwise nothing is
/// touched. With `pauseAt`, the call of that number holds until `resume()`. Set everything before the action runs.
final class FakeBoxTrash: Trashing, @unchecked Sendable {
    private let lock = NSCondition()
    private var received: [URL] = []
    private var count = 0
    private var held = false
    private var released = false
    var refusing: Set<String> = []
    /// What a refused path throws.
    var refusal = ShelfError.trashFailed
    var removes = false
    var folder: URL?
    var pauseAt = 0

    var calls: [URL] { lock.withLock { received } }
    var isHeld: Bool { lock.withLock { held } }

    func trash(_ url: URL) throws(ShelfError) -> URL? {
        hold()
        guard !refusing.contains(url.lastPathComponent) else { throw refusal }
        lock.withLock { received.append(url) }
        if removes {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard let folder else { return url }
        let place = folder.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.moveItem(at: url, to: place)
        } catch {
            throw .trashFailed
        }
        return place
    }

    func resume() {
        lock.withLock {
            released = true
            lock.broadcast()
        }
    }

    private func hold() {
        lock.withLock {
            count += 1
            guard count == pauseAt else { return }
            held = true
            while !released { lock.wait() }
        }
    }
}

/// Locate…'s open panel: a fixed answer (nil = cancelled) and the names it was asked for.
@MainActor
final class FakeLocator: FileLocating {
    var answer: URL?
    private(set) var asked: [String] = []

    func locate(_ name: String, lastSeenIn folder: URL?) async -> URL? {
        asked.append(name)
        return answer
    }
}

/// The executor's exclusive rename, holding before the `pauseAt`th call until `resume()`, so a test can press Cancel
/// while a Move or Copy is between items.
nonisolated final class RenameGate: @unchecked Sendable {
    private let lock = NSCondition()
    private let pauseAt: Int
    private var calls = 0
    private var held = false
    private var released = false

    init(pauseAt: Int) { self.pauseAt = pauseAt }

    var isHeld: Bool { lock.withLock { held } }

    var rename: MoveExecutor.Rename {
        { [self] from, to in
            lock.withLock {
                calls += 1
                guard calls == pauseAt else { return }
                held = true
                while !released { lock.wait() }
            }
            return MoveExecutor.renameExclusive(from, to)
        }
    }

    func resume() {
        lock.withLock {
            released = true
            lock.broadcast()
        }
    }
}
