import SwiftUI
import ZivletNotchCore

/// What a client of the island provides (design/19 §8): a view per surface, the island group's accessibility text,
/// and answers to the island's notices. Nothing here names jobs, batches or files; the Notch HUD is the client now,
/// the tray and the picker later.
public protocol IslandClient: AnyObject {
    func content(for surface: IslandSurface, display: UInt32) -> AnyView
    func accessibilityLabel(display: UInt32) -> String
    /// The same text the expanded view shows, so a screen reader never needs hover (D-M5a-4).
    func accessibilityValue(display: UInt32) -> String
    /// The custom action that opens the island without a pointer (D-N12).
    var accessibilityActionName: String { get }
    func accessibilityActionPerformed(display: UInt32)
    /// The island's hold changed (pointer, accessibility focus or a drag from it); lingers pause or restart (D-N13).
    func held(_ held: Bool, display: UInt32, now: Duration)
    /// Escape on a closable card.
    func closeRequested(display: UInt32)
    /// The display set changed; items on a removed display move to its replacement (design/19 §5.2).
    func displaysChanged(_ ids: [UInt32], replacing: [UInt32: UInt32])
    /// The display's island goes to `surface`, before its content for it is asked for: a client can bring what an
    /// open card shows up to date first (19b §6.2).
    func surfaceChanged(_ surface: IslandSurface, display: UInt32)
}

extension IslandClient {
    public func surfaceChanged(_ surface: IslandSurface, display: UInt32) {}
}
