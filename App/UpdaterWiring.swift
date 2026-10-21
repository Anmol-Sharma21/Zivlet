import Foundation
import Sparkle
import ZivletSettings
import ZivletUI
import os

/// Sparkle 2 (P1-53, D-M4-11). The updater is created and started only when the Info.plist feed and key are real
/// (`UpdaterConfiguration`); with this repository's placeholder feed and empty key it never exists, so "Check for
/// Updates…" stays disabled and nothing reaches a network. Settings › Updates drives automatic checks and downloads.
final class UpdaterWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "updates")
    let configuration: UpdaterConfiguration
    private var controller: SPUStandardUpdaterController?

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        configuration = UpdaterConfiguration.from(infoDictionary: infoDictionary)
    }

    /// Nil while the updater is not running, which disables the menu item and Check Now.
    var checkForUpdates: (() -> Void)? {
        guard let controller else { return nil }
        return { controller.checkForUpdates(nil) }
    }

    func start(with settings: UpdatesGroup) {
        guard case .enabled = configuration else {
            if case .disabled(let reason) = configuration {
                logger.notice("Updater not started: \(reason.rawValue, privacy: .public)")
            }
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
        } catch {
            logger.error("Updater failed to start: \(String(describing: error), privacy: .private)")
            return
        }
        self.controller = controller
        apply(settings)
        logger.notice("Updater started")
    }

    func apply(_ settings: UpdatesGroup) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = settings.automaticChecks
        updater.automaticallyDownloadsUpdates = settings.automaticChecks && settings.automaticDownloads
    }
}
