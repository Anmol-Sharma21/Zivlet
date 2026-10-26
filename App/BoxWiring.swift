import AppKit
import ZivletActions
import ZivletBox
import ZivletCore
import ZivletSettings
import ZivletShelfCore
import os

/// The Drop Box in the app (P2-55, P2-141): one controller over the standard stores, restored at launch and saved at
/// quit; the BOX slice's adapter; the menu command; drop results and save errors shown as action toasts and cards.
/// Settings › Drop Box: "BOX on the wheel adds to" decides the slice's box here (a drop on the panel or at the notch
/// always goes to the box it lands on, OWN-APP-1) and "Clear items" is the controller's auto-clear policy; "Open at
/// the notch while dragging" and "Shake to open" are read by the tray and its driver. A change to Reduce
/// Transparency, Increase Contrast or Reduce Motion redraws a shown panel at once (19c §6).
final class BoxWiring {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")
    /// Undo on the Clear toast put the items back.
    static let restoredMessage = "Back in the box."
    let controller: BoxController
    let settings: () -> BoxGroup
    /// Shows a result where the placement says (set by the composition root).
    var present: (ActionResult, CGPoint?) -> Void = { _, _ in }
    /// The notch tray and what drives it (`BoxWiring+Tray.swift`).
    var tray: TrayClient?
    var driver: TrayDriver?
    var zoneWatch: Task<Void, Never>?
    private var displayOptions: (any NSObjectProtocol)?
    #if DEBUG
        let previewFlags: BoxShotFlags
        var previewBox: TrayPreviewBox?
    #endif

    init(settings: @escaping () -> BoxGroup, ports: BoxPorts = .standard(), actions: BoxActions) {
        self.settings = settings
        #if DEBUG
            previewFlags = BoxShots.flags()
        #endif
        controller = BoxController(ports: ports, actions: actions)
        controller.onAdded = { [weak self] outcome in self?.present(outcome.actionResult, nil) }
        controller.onError = { [weak self] message in self?.present(.failed(ActionCard(title: message)), nil) }
        controller.onPresented = { base, frame in Self.log(base, frame: frame) }
        controller.onResult = { [weak self] result, frame in self?.present(result, frame.map(Self.anchor)) }
        controller.autoClear = { [settings] in AutoClear(rawValue: settings().autoClear.rawValue) ?? .off }
        displayOptions = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated { controller?.displayOptionsChanged() }
        }
    }

    /// A bulk action's toast or card sits under the panel's centre when the placement is near the drop.
    private static func anchor(_ frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.minY) }

    /// `Box: <state>` and `Box: frame x y w h` (whole points from the top of the menu-bar display): states and
    /// frames only, never names, so the lines are public for the demo scripts.
    private static func log(_ base: BoxPresentation.Base, frame: CGRect?) {
        logger.notice("Box: \(base.stored, privacy: .public)")
        guard let frame, let top = NSScreen.screens.first?.frame.maxY else { return }
        let values = [frame.minX, top - frame.maxY, frame.width, frame.height].map { String(Int($0.rounded())) }
        logger.notice("Box: frame \(values.joined(separator: " "), privacy: .public)")
    }

    /// The BOX slice's port into the box.
    lazy var adding: any BoxAdding = BoxSliceAdding(
        controller: controller, newBoxByDefault: { [settings] in settings().dropsGo == .newBox })

    /// Loads the boxes and puts the panel back as it was; nothing is resolved until it shows its items.
    func start() { controller.start() }

    /// "Show Drop Box".
    func show() { controller.showPanel(.saved) }

    func quit() {
        zoneWatch?.cancel()
        if let displayOptions { NSWorkspace.shared.notificationCenter.removeObserver(displayOptions) }
        controller.quit()
    }
}
