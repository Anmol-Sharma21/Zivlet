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

/// A Trash that records what it was given and refuses the paths in `refusing`; nothing is really trashed.
final class FakeBoxTrash: Trashing, @unchecked Sendable {
    private let lock = NSLock()
    private var received: [URL] = []
    var refusing: Set<String> = []

    var calls: [URL] { lock.withLock { received } }

    func trash(_ url: URL) throws(ShelfError) {
        guard !refusing.contains(url.lastPathComponent) else { throw .trashFailed }
        lock.withLock { received.append(url) }
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
