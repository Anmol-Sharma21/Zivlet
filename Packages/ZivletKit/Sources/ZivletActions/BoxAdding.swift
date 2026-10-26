import Foundation

/// The Drop Box as the BOX slice sees it (P2-55 §9.5, OWN-APP-1): add the dropped files to the current box, or to a
/// new one when ⌥ is held, and say what happened. The box module implements it; the actions never import it.
public protocol BoxAdding {
    func add(_ urls: [URL], newBox: Bool) async -> ActionResult
}
