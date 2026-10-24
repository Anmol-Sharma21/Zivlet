import AppKit
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger
import ZivletUI
import os

/// The notch island in the app (D-M5a-9): one `ScreenGeometryReader`, one `IslandHosts` and one `NotchHUD`, shared
/// by the conversion and action wirings; M5b's tray registers with the same hosts. It forwards the wheel's shows and
/// hides (D-M5a-6), Reduce Motion, and VoiceOver or Switch Control (D-N13), and logs each applied surface for the
/// demo: surface names and whole-number frames only.
final class IslandWiring {
    let reader = ScreenGeometryReader()
    let hosts: IslandHosts
    let hud: NotchHUD
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")
    private var observers: [any NSObjectProtocol] = []
    private var keyValueObservers: [NSKeyValueObservation] = []

    init() {
        hosts = IslandHosts(provider: reader)
        hud = NotchHUD(hosts: hosts, provider: reader)
        hosts.onSurface = { [logger] _, surface, frame in Self.log(surface, frame: frame, logger: logger) }
        followAccessibility()
    }

    var hasBuiltInNotch: Bool { reader.hasBuiltInNotch }
    var hasItems: Bool { hosts.hasItems }
    /// The island can draw: there is a display now and the Notch HUD has one to show on. When this is false a new
    /// batch or action goes near the drop instead (the route falls back), so nothing is filed where nothing draws.
    var canShow: Bool { !reader.displays.isEmpty && hud.canShow }

    /// The wheel's effects as the trigger sends them: the island steps aside while the wheel shows (W-8).
    func wheel(_ effect: TriggerEffect) {
        switch effect {
        case .show: hosts.wheelShown()
        case .hide: hosts.wheelHidden()
        default: break
        }
    }

    /// Reduce Transparency and Increase Contrast pick the island's finish (19b D-NL3).
    private static func finishSettings(_ workspace: NSWorkspace) -> IslandFinish.Settings {
        IslandFinish.Settings(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
    }

    private func followAccessibility() {
        let workspace = NSWorkspace.shared
        if workspace.accessibilityDisplayShouldReduceMotion { hosts.reduceMotionChanged(true) }
        hosts.finishSettingsChanged(Self.finishSettings(workspace))
        let options = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let workspace = NSWorkspace.shared
                self?.hosts.reduceMotionChanged(workspace.accessibilityDisplayShouldReduceMotion)
                self?.hosts.finishSettingsChanged(Self.finishSettings(workspace))
            }
        }
        observers = [options]
        let update: @Sendable (NSWorkspace, Any) -> Void = { [weak self] _, _ in
            Task { @MainActor in self?.assistiveTechChanged() }
        }
        keyValueObservers = [
            workspace.observe(\.isVoiceOverEnabled, options: [.initial, .new], changeHandler: update),
            workspace.observe(\.isSwitchControlEnabled, options: [.initial, .new], changeHandler: update),
        ]
    }

    private func assistiveTechChanged() {
        let workspace = NSWorkspace.shared
        hud.assistiveTechChanged(workspace.isVoiceOverEnabled || workspace.isSwitchControlEnabled)
    }

    /// `Island: <surface>` and `Island: frame <x> <y> <w> <h>` in screen-capture points: the origin at the top left
    /// of the menu-bar display, y down, so `screencapture -R` can crop the island from the line.
    private static func log(_ surface: IslandSurface, frame: CGRect, logger: Logger) {
        let name = String(describing: surface)
        logger.notice("Island: \(name, privacy: .public)")
        guard surface != .hidden, let top = NSScreen.screens.first?.frame.maxY else { return }
        let (x, y) = (Int(frame.minX.rounded()), Int((top - frame.maxY).rounded()))
        let (width, height) = (Int(frame.width.rounded()), Int(frame.height.rounded()))
        logger.notice(
            "Island: frame \(x, privacy: .public) \(y, privacy: .public) \(width, privacy: .public) \(height, privacy: .public)"
        )
    }
}
