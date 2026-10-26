import SwiftUI
import ZivletCore
import ZivletNotch
import ZivletNotchCore

/// What the tray draws and says on each surface (19c §4.2, §4.3, §6): the drop row, the result toast, the compact
/// view as the expanded card, nothing on the sensor.
extension TrayClient: IslandClient {
    public func content(for surface: IslandSurface, display: UInt32) -> AnyView {
        switch surface {
        case .dropTarget:
            return AnyView(TrayDropRow(count: dropTarget?.count ?? 0, inBox: box.trayCount))
        case .toast:
            guard let lastToast, lastToast.display == display else { return AnyView(EmptyView()) }
            return AnyView(TrayToastRow(toast: lastToast) { [weak self] in self?.undoLastDrop() })
        case .expanded:
            // Only when the compact view really shows: the island also measures this content while it rests, and
            // nothing may be resolved then (P2-141).
            if hosts.surface(on: display) == .expanded { prepareExpanded(on: display) }
            return AnyView(
                BoxCompactView(
                    model: box.trayModel, press: { [weak self] in self?.pressed($0, display: display) },
                    drag: { [weak self] in self?.stripDrag($0, display: display) }))
        case .hidden, .collapsed, .sensor:
            return AnyView(EmptyView())
        }
    }

    public func accessibilityLabel(display: UInt32) -> String { Self.label }

    /// The spoken header: "Drop Box, 12 items, 84 megabytes", or the drop target's sentence while it shows.
    public func accessibilityValue(display: UInt32) -> String {
        if let dropTarget, dropTarget.display == display { return BoxSpeech.dropTarget(dropTarget.count) }
        return BoxSpeech.header(count: box.trayCount, bytes: box.trayBytes)
    }

    /// Once each time the compact view opens on `display`: the box resolves and loads the strip's thumbnails, and
    /// each arrival redraws the open content.
    private func prepareExpanded(on display: UInt32) {
        guard preparedDisplays.insert(display).inserted else { return }
        box.prepareTray { [weak self] in
            guard let self, hosts.activeClient(on: display) == .tray, hosts.surface(on: display) == .expanded
            else { return }
            hosts.contentChanged(on: display)
        }
    }

    public var accessibilityActionName: String { BoxCopy.title(.openPanel) }

    public func accessibilityActionPerformed(display: UInt32) { openPanel(from: display) }

    /// A held island keeps its toast: the linger stops while held and starts again when let go.
    public func held(_ held: Bool, display: UInt32, now: Duration) {
        if held { heldDisplays.insert(display) } else { heldDisplays.remove(display) }
        guard lastToast?.display == display else { return }
        if held { toastTask?.cancel() } else { startLinger() }
    }

    public func closeRequested(display: UInt32) {}

    /// Leaving the compact view means the next time it opens it resolves again.
    public func surfaceChanged(_ surface: IslandSurface, display: UInt32) {
        if surface != .expanded { preparedDisplays.remove(display) }
    }

    public func displaysChanged(_ ids: [UInt32], replacing: [UInt32: UInt32]) {
        if let dropTarget, !ids.contains(dropTarget.display) { self.dropTarget = nil }
        rest()
    }

    /// A press in the compact view: "Open Drop Box" (and "+6") opens the panel below the island; the rest goes to
    /// the box.
    func pressed(_ press: BoxPress, display: UInt32) {
        guard press == .openPanel else { return box.press(press) }
        openPanel(from: display)
    }

    /// The full panel, below the island, centred on it (19c §4.4); the tray goes back to rest.
    func openPanel(from display: UInt32) {
        let island = hosts.host(on: display).map { Rect2D($0.frame) }
        box.showPanel(island.map(BoxAnchor.below) ?? .saved)
        if hosts.surface(on: display) == .expanded { hosts.request(nil, from: .tray) }
        rest()
    }
}
