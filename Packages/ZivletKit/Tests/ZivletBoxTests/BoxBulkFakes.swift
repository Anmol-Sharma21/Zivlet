import AppKit
import ZivletActions

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
