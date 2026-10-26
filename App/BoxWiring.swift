import AppKit
import ZivletActions
import ZivletBox
import ZivletCore
import ZivletSettings
import ZivletShelfCore

/// The Drop Box in the app (P2-55, P2-141): one controller over the standard stores, restored at launch and saved at
/// quit; the BOX slice's adapter; the menu command; drop results and save errors shown as action toasts and cards.
/// Settings › Drop Box: "New drops go to" decides the slice's box here; the tray, shake and auto-clear rows are read
/// by the parts that use them as they are added (plan 16 streams C and D).
final class BoxWiring {
    let controller: BoxController
    private let settings: () -> BoxGroup
    /// Shows a result where the placement says (set by the composition root).
    var present: (ActionResult, CGPoint?) -> Void = { _, _ in }

    init(settings: @escaping () -> BoxGroup, ports: BoxPorts = .standard()) {
        self.settings = settings
        controller = BoxController(ports: ports)
        controller.onAdded = { [weak self] outcome in self?.present(outcome.actionResult, nil) }
        controller.onError = { [weak self] message in self?.present(.failed(ActionCard(title: message)), nil) }
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
