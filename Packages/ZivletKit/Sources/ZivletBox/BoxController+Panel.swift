import AppKit
import SwiftUI
import ZivletCore
import ZivletShelfCore

extension BoxController {
    /// The panel's content view takes drops; the SwiftUI views sit inside it.
    func wirePanel() {
        hosting.autoresizingMask = [.width, .height]
        dropView.addSubview(hosting)
        panel.contentView = dropView
        panel.onEscape = { [weak self] in self?.apply(.escape) }
        panel.onKey = { [weak self] event in self?.handleKey(BoxKeyStroke(event)) ?? false }
        panel.onMoveEnded = { [weak self] frame in self?.panelMoved(to: Rect2D(frame)) }
        dropView.accepts = { [weak self] in self?.presentation.acceptsDrop ?? false }
        dropView.onEnter = { [weak self] count in
            guard let self, presentation.overlay != .dropTarget(count: count) else { return }
            dragEntered(count: count)
        }
        dropView.onExit = { [weak self] in self?.dragExited() }
        // Promises must be received inside `performDragOperation`, so the work starts at once, not on a later turn.
        dropView.onDrop = { [weak self] pasteboard in
            Task.immediate { @MainActor in
                guard let self else { return }
                self.onAdded(await self.receiveDrop(pasteboard))
            }
        }
    }

    /// Draws the presentation: the content, the frame for its base, on or off screen.
    func render() {
        let model = viewModel
        rendered = model
        renders += 1
        hosting.rootView = AnyView(BoxPanelView(model: model) { [weak self] in self?.press($0) })
        guard let frame = frame(for: model) else {
            panel.orderOut(nil)
            report(nil)
            return
        }
        if panel.frame != frame.cgRect { panel.setFrame(frame.cgRect, display: true) }
        if !panel.isVisible { panel.show() }
        report(frame.cgRect)
    }

    /// Reduce Transparency or Increase Contrast changed: a shown panel takes the new finish at once (19c §6).
    public func displayOptionsChanged() {
        guard panel.isVisible else { return }
        render()
    }

    private func report(_ frame: CGRect?) {
        if let lastReport, lastReport.base == presentation.base, lastReport.frame == frame { return }
        lastReport = (presentation.base, frame)
        onPresented(presentation.base, frame)
    }

    /// The display a frame sits on, else the first one.
    func display(for frame: Rect2D?) -> Rect2D {
        let displays = ports.visibleFrames()
        let first = displays.first ?? Rect2D(x: 0, y: 0, width: 1440, height: 900)
        guard let frame else { return first }
        return displays.first { $0.contains(Point2D(x: frame.midX, y: frame.midY)) } ?? first
    }

    /// The panel's frame: the tab against its edge at the saved height, or the card with its top where it was.
    func frame(for model: BoxViewModel) -> Rect2D? {
        let size = BoxLayout.size(of: model)
        guard size != .zero else { return nil }
        let display = display(for: current?.frame)
        let anchor = current?.frame ?? defaultFrame(in: display)
        switch presentation.base {
        case .docked(let edge):
            return DockSnapper.tabFrame(
                edge: edge, panel: anchor, in: display, width: Double(size.width), height: Double(size.height))
        case .hidden, .collapsed, .expanded:
            let top = Rect2D(
                x: anchor.minX, y: anchor.maxY - Double(size.height), width: Double(size.width),
                height: Double(size.height))
            return PanelFrames.clamped(top, to: ports.visibleFrames())
        }
    }

    /// The first place: against the right edge of the menu-bar display, around its middle (19c §4.4).
    func defaultFrame(in display: Rect2D) -> Rect2D {
        let width = Double(BoxLook.Panel.width)
        let height = Double(BoxLook.Panel.minHeight)
        return Rect2D(
            x: display.maxX - width - PanelFrames.inset, y: display.midY - height / 2, width: width, height: height)
    }

    /// Sets where the panel will open before it is shown.
    func place(_ anchor: BoxAnchor) {
        switch anchor {
        case .saved:
            guard current?.frame == nil, presentation.dock == nil else { return }
            presentation = presentation.withDock(.right)
        case .point(let point):
            let display = display(for: Rect2D(x: point.x, y: point.y, width: 0, height: 0))
            let frame = PanelFrames.placed(
                width: Double(BoxLook.Panel.width), height: Double(BoxLook.Panel.minHeight), near: point, in: display)
            savePlace(frame: Rect2D(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
            presentation = presentation.withDock(nil)
        case .below(let island):
            place(.point(Point2D(x: island.midX, y: island.minY - PanelFrames.inset)))
        }
    }
}

extension BoxPresentation {
    /// The same presentation remembering another dock edge, without moving the panel.
    func withDock(_ edge: DockEdge?) -> BoxPresentation {
        BoxPresentation(base: base, overlay: overlay, dock: edge, missing: missing, isEmpty: isEmpty)
    }
}
