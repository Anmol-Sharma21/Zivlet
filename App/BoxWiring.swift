import AppKit
import ZivletActions
import ZivletBox
import ZivletCore
import ZivletSettings
import ZivletShelfCore
import os

/// The Drop Box in the app (P2-55, P2-141): one controller over the standard stores, restored at launch and saved at
/// quit; the BOX slice's adapter; the menu command; drop results and save errors shown as action toasts and cards.
/// Settings › Drop Box: "New drops go to" decides the slice's box here; the tray, shake and auto-clear rows are read
/// by the parts that use them as they are added (plan 16 streams C and D).
final class BoxWiring {
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")
    let controller: BoxController
    private let settings: () -> BoxGroup
    /// Shows a result where the placement says (set by the composition root).
    var present: (ActionResult, CGPoint?) -> Void = { _, _ in }

    init(settings: @escaping () -> BoxGroup, ports: BoxPorts = .standard(), actions: BoxActions) {
        self.settings = settings
        controller = BoxController(ports: ports, actions: actions)
        controller.onAdded = { [weak self] outcome in self?.present(outcome.actionResult, nil) }
        controller.onError = { [weak self] message in self?.present(.failed(ActionCard(title: message)), nil) }
        controller.onPresented = { base, frame in Self.log(base, frame: frame) }
        controller.onResult = { [weak self] result, frame in self?.present(result, frame.map(Self.anchor)) }
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

    func quit() { controller.quit() }
}
