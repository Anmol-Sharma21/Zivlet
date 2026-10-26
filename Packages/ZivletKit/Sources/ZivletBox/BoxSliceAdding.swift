import AppKit
import ZivletActions
import ZivletCore

/// The BOX slice's way into the box (P2-55 §9.5, OWN-APP-1): add to the current box, or a new one when ⌥ is held or
/// the setting says so, then open the panel at the drop point (19c §4.4). The result is the toast or card.
public final class BoxSliceAdding: BoxAdding {
    private let controller: BoxController
    private let newBoxByDefault: () -> Bool
    private let dropPoint: () -> Point2D?

    public init(
        controller: BoxController, newBoxByDefault: @escaping () -> Bool,
        dropPoint: @escaping () -> Point2D? = {
            let p = NSEvent.mouseLocation
            return Point2D(x: p.x, y: p.y)
        }
    ) {
        self.controller = controller
        self.newBoxByDefault = newBoxByDefault
        self.dropPoint = dropPoint
    }

    public func add(_ urls: [URL], newBox: Bool) async -> ActionResult {
        let outcome = await controller.add(urls, newBox: newBox || newBoxByDefault())
        if outcome.added > 0 { controller.showPanel(dropPoint().map(BoxAnchor.point) ?? .saved) }
        return outcome.actionResult
    }
}

extension AddOutcome {
    /// The toast and card for an add (19c §5): "Added 3"; a card for what was left out; "Already in the box" when
    /// every item was there; the reason when nothing could be added.
    public var actionResult: ActionResult {
        let lines = duplicates.map { "\($0) is already in the box." } + rejected
        if let toast {
            guard !lines.isEmpty else { return .done(toast: toast, undo: nil) }
            return .partial(toast: toast, card: ActionCard(title: "Some items weren't added.", lines: lines), undo: nil)
        }
        if !duplicates.isEmpty, rejected.isEmpty { return .done(toast: "Already in the box", undo: nil) }
        let title = failure.map { $0.hasSuffix(".") ? $0 : $0 + "." } ?? "Nothing was added."
        return .failed(ActionCard(title: title, lines: rejected.filter { $0 != failure }))
    }
}
