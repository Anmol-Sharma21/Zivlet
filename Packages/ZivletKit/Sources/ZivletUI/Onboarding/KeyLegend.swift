import AppKit
import SwiftUI
import ZivletCore
import ZivletSettings
import ZivletTrigger

/// The coach after onboarding (P1-47): for the first three real drags a small legend of the wheel keys sits beside
/// the wheel, counted down in `onboarding.practiceDragsLeft`.
public enum KeyLegend {
    static let gap: CGFloat = 12
    static let margin: CGFloat = 12

    /// "⇧ Convert · ⌘ Tools · ⌃ Actions" from the current bindings.
    public static func text(_ bindings: TriggerBindings) -> String {
        WheelMode.allCases.map { "\(bindings.modifier(for: $0).symbols) \(PracticeCoordinator.name($0))" }
            .joined(separator: " · ")
    }

    public static func shows(_ onboarding: OnboardingGroup) -> Bool {
        onboarding.completed && onboarding.practiceDragsLeft > 0
    }

    /// One drag with the legend shown.
    public static func counting(_ onboarding: OnboardingGroup) -> OnboardingGroup {
        var copy = onboarding
        copy.practiceDragsLeft = max(0, onboarding.practiceDragsLeft - 1)
        return copy
    }

    /// Right of the wheel, or left when the right side has no room; vertically centred, kept inside the screen.
    public static func frame(size: CGSize, beside wheel: CGRect, screen: CGRect) -> CGRect {
        let inside = screen.insetBy(dx: margin, dy: margin)
        let rightX = wheel.maxX + gap
        let x = rightX + size.width <= inside.maxX ? rightX : wheel.minX - gap - size.width
        let y = min(max(wheel.midY - size.height / 2, inside.minY), inside.maxY - size.height)
        return CGRect(origin: CGPoint(x: max(x, inside.minX), y: y), size: size)
    }
}

/// The legend's panel: non-activating, never takes the mouse, above the wheel.
public final class KeyLegendPanel {
    static let size = CGSize(width: 300, height: 34)

    private let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: KeyLegendPanel.size), styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: true)
    private let hosting = NSHostingView(rootView: KeyLegendView(text: ""))

    public init() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
    }

    public var isVisible: Bool { panel.isVisible }

    public func show(_ text: String, beside wheel: CGRect) {
        hosting.rootView = KeyLegendView(text: text)
        let screen =
            NSScreen.screens.first { $0.frame.intersects(wheel) }?.visibleFrame ?? wheel.insetBy(dx: -400, dy: -400)
        panel.setFrame(KeyLegend.frame(size: Self.size, beside: wheel, screen: screen), display: false)
        panel.orderFrontRegardless()
    }

    public func hide() { panel.orderOut(nil) }
}

struct KeyLegendView: View {
    let text: String

    var body: some View {
        Text(text).font(.callout.weight(.medium)).padding(.horizontal, 14)
            .frame(width: KeyLegendPanel.size.width, height: KeyLegendPanel.size.height)
            .glassEffect(.regular, in: .capsule)
    }
}
