import AppKit
import SwiftUI
import ZivletCore
import ZivletTrigger
import ZivletWheelCore
import os

public protocol WheelControllerDelegate: AnyObject {
    func wheelController(_ controller: WheelController, didSelect selection: WheelSelection)
}

/// Owns the panel, the store and the current payload. Executes the trigger's wheel effects and answers the drop
/// view (03a §2). Nothing here converts files: a drop becomes a `WheelSelection` for the delegate.
public final class WheelController {
    public weak var delegate: (any WheelControllerDelegate)?
    /// The drag session ended on the panel (dropped or refused); the trigger host maps it to `.dropHandled`.
    public var onDragEnded: () -> Void = {}
    public private(set) var isPointerInside = false
    /// Targets this machine cannot produce (probed engines, 03a §3.5); their slices are left off (FR-08).
    public var capabilities = CapabilitySnapshot.full
    /// Whether ⌥ is down at drop; the event state needs no permission. Replaced in tests.
    public var isOptionHeld: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.option) }
    func isPointerInsideWheel(_ inside: Bool) { isPointerInside = inside }
    public let store: WheelStore
    let panel = WheelPanel()
    /// Where the wheel's panel is on screen (global, y up), for things placed beside it.
    public var panelFrame: CGRect { panel.frame }

    let reader: DragPayloadReader
    let builder: SliceBuilder
    let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "wheel")
    private let placer = PanelPlacer()
    private let screens: @MainActor () -> [ScreenFrame]
    private let appearance: @MainActor () -> WheelAppearance
    private(set) var payload: DragPayload?
    private var generation = 0
    private let frameSignpost: TriggerFrameSignpost
    private var firstFrame: FirstFrameWatch?

    public init(
        reader: DragPayloadReader, builder: SliceBuilder = SliceBuilder(),
        feedback: any WheelFeedback = SystemWheelFeedback(),
        screens: @escaping @MainActor () -> [ScreenFrame] = WheelController.systemScreens,
        appearance: @escaping @MainActor () -> WheelAppearance = { WheelAppearance.current() },
        frameSignpost: TriggerFrameSignpost = .shared
    ) {
        self.reader = reader
        self.frameSignpost = frameSignpost
        self.builder = builder
        self.screens = screens
        self.appearance = appearance
        store = WheelStore(feedback: feedback)
        let side = WheelGeometry.standard.panelSide
        let dropView = WheelDropView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        let hosting = NSHostingView(rootView: WheelView(store: store))
        hosting.sizingOptions = []
        hosting.frame = dropView.bounds
        hosting.autoresizingMask = [.width, .height]
        dropView.addSubview(hosting)
        panel.contentView = dropView
        dropView.handler = self
    }

    public static func systemScreens() -> [ScreenFrame] {
        NSScreen.screens.map { ScreenFrame(frame: Rect2D($0.frame), visibleFrame: Rect2D($0.visibleFrame)) }
    }

    /// Builds the view tree and glass once at launch, off-screen at alpha 0, so the first real show only moves the
    /// panel and swaps the model (14 §2.1).
    public func prewarm() async {
        generation += 1
        let mine = generation
        let warm = WheelModel(
            mode: .actions, content: builder.content(for: .actions, items: [SelectionItem(.png)]), idleHubLabel: "")
        store.present(warm, emptyMessage: nil, appearance: appearance())
        store.expand()
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(50))
        guard mine == generation else { return }
        panel.orderOut(nil)
        store.dismiss()
    }

    public func apply(_ effect: TriggerEffect) {
        switch effect {
        case .show(let mode, let anchor):
            guard let payload = reader.latest else { return logger.error("Wheel show without a payload; ignored") }
            show(mode, at: anchor, payload: payload)
        case .switchTo(let mode): switchTo(mode)
        case .reject(let mode, _): reject(mode)
        case .hide: hide()
        default: break
        }
    }

    /// Centre on `anchor` (global, y up), clamped so the disk stays on screen; fade in over 70 ms.
    public func show(_ mode: WheelMode, at anchor: Point2D, payload: DragPayload) {
        guard let placement = placer.place(pointer: anchor, screens: screens()) else {
            return logger.error("Wheel show with no screens; ignored")
        }
        generation += 1
        self.payload = payload
        let content = builder.content(for: mode, items: payload.items, capabilities: capabilities)
        let model = WheelModel(
            mode: mode, content: content, idleHubLabel: HubLabel.text(for: payload.hubItems),
            hubIsCompact: HubLabel.isCompact(for: payload.hubItems))
        store.present(model, emptyMessage: emptyMessage(content), appearance: appearance())
        panel.setFrame(placement.panelFrame.cgRect, display: false)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        firstFrame?.cancel()
        firstFrame = FirstFrameWatch(view: panel.contentView) { [frameSignpost] in frameSignpost.end() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WheelTiming.fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        let detail = "\(mode.rawValue), \(model.slices.count) slices, \(store.theme.rawValue)"
        logger.notice("Wheel shown: \(detail, privacy: .public)")
    }

    #if DEBUG
        /// DEBUG demo: the scenario's wheel at the centre of the first screen's visible frame, no drag needed.
        public func showDemo(_ scenario: DemoScenario) {
            guard let visible = screens().first?.visibleFrame else { return logger.error("Demo wheel: no screens") }
            frameSignpost.begin()  // no tap in the demo: the interval starts at the show
            show(scenario.mode, at: Point2D(x: visible.midX, y: visible.midY), payload: scenario.payload)
            if let slot = scenario.highlight { store.pointer(.slot(slot)) }
        }
    #endif

    /// 80 ms fade, then order out and reset. A show during the fade wins.
    public func hide() {
        generation += 1
        let mine = generation
        isPointerInsideWheel(false)
        store.cancelExpansion()
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WheelTiming.hide
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHide(mine) }
        }
    }

    private func finishHide(_ mine: Int) {
        guard mine == generation else { return }
        panel.orderOut(nil)
        store.dismiss()
        payload = nil
    }

    private func switchTo(_ mode: WheelMode) {
        guard let current = store.model, let payload else { return }
        let content = builder.content(for: mode, items: payload.items, capabilities: capabilities)
        store.switchTo(current.switching(to: mode, content: content), emptyMessage: emptyMessage(content))
    }

    /// The refused wheel's own reason, shown for 1.2 s while the current wheel stays (03a §1.4 T12).
    private func reject(_ mode: WheelMode) {
        let content = builder.content(for: mode, items: payload?.items ?? [], capabilities: capabilities)
        store.reject(message: emptyMessage(content) ?? builder.message(for: .noItems))
    }

    private func emptyMessage(_ content: WheelContent) -> String? {
        if case .empty(let reason) = content { return builder.message(for: reason) }
        return nil
    }
}

extension Rect2D {
    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
