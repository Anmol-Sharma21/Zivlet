import AppKit
import ZivletSettings
import ZivletUI
import ZivletWheelCore
import os

/// Shows onboarding until it is finished (P1-47, 03b §8.2), resumes at the stored page, and reopens the practice
/// page from the menu. Finish applies the login choice; page 7 offers Move to Applications when needed.
final class OnboardingWiring {
    /// DEBUG: `-ZivletResetOnboarding YES` starts onboarding from the beginning.
    static let resetKey = "ZivletResetOnboarding"

    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
    private let store: SettingsStore
    private var controller: OnboardingWindowController?
    private(set) var model: OnboardingModel?
    /// Onboarding was finished (text recognition warms up then, P2-103).
    var onFinished: () -> Void = {}

    init(store: SettingsStore) {
        self.store = store
    }

    /// At launch: only while unfinished, and never during a DEBUG demo or UI test run.
    func showIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: Self.resetKey) {
                store.update { $0.with(\.onboarding, OnboardingGroup()) }
            }
        #endif
        var demoPrefixes = ["-ZivletDemo"]
        #if DEBUG
            demoPrefixes += ["-ZivletCopyTextDemo", "-ZivletTextStates"]  // never compiled into Release
        #endif
        let isDemoRun = arguments.contains { argument in
            demoPrefixes.contains { argument.hasPrefix($0) } || argument == "-UITestFixture"
        }
        guard !store.current.onboarding.completed, !isDemoRun else {
            return
        }
        show(nil)
    }

    /// Opens onboarding at `page`, or at the stored page.
    func show(_ page: OnboardingPage?) {
        let model = OnboardingModel(
            settings: store.current, commands: commands(), loginItemIsOn: LoginItemModel().isOn)
        model.sampleURL = sample()
        if let page { model.show(page) }
        let controller = OnboardingWindowController(model: model)
        self.controller?.close()
        self.controller = controller
        self.model = model
        controller.show()
        let window = controller.window?.windowNumber ?? 0
        logger.notice(
            "Onboarding shown at page \(model.flow.page.rawValue, privacy: .public) window \(window, privacy: .public)")
    }

    private func commands() -> OnboardingCommands {
        let bundle = Bundle.main.bundleURL
        return OnboardingCommands(
            write: { [store] transform in
                store.update(transform)
                return store.current
            },
            finished: { [weak self] wantsLoginItem in self?.finish(wantsLoginItem: wantsLoginItem) },
            moveToApplications: AppLocation.needsMove(bundlePath: bundle.path) ? { await Self.move(bundle) } : nil,
            revealSample: { url in NSWorkspace.shared.activateFileViewerSelecting([url]) })
    }

    /// Selections made while a practice page is up are taken by onboarding and never run.
    func receive(_ selection: WheelSelection) -> Bool {
        guard controller?.window?.isVisible == true, let model, model.receive(selection) else { return false }
        logger.notice("Practice selection: \(selection.mode.rawValue, privacy: .public)")
        return true
    }

    private func sample() -> URL? {
        do {
            return try OnboardingSample.make(in: OnboardingSample.standardFolder)
        } catch {
            logger.error("Practice file not drawn: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    private func finish(wantsLoginItem: Bool) {
        let login = LoginItemModel()
        login.setOn(wantsLoginItem)
        logger.notice("Onboarding finished; login item \(login.isOn ? "on" : "off", privacy: .public)")
        controller?.close()
        controller = nil
        model = nil
        onFinished()
    }

    /// Copies to /Applications off the main actor, opens the copy as a new process and quits this one only once
    /// that process exists; a failure returns its sentence and this copy keeps running.
    private static func move(_ bundle: URL) async -> String? {
        let copied: URL
        do {
            copied = try await AppLocation.copyInBackground(bundle: bundle)
        } catch {
            return error.message
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let launched: NSRunningApplication
        do {
            launched = try await NSWorkspace.shared.openApplication(at: copied, configuration: configuration)
        } catch {
            Logger(subsystem: "app.zivlet.Zivlet", category: "app").error(
                "The copy in Applications did not open: \(String(describing: error), privacy: .private)")
            return AppLocation.MoveFailure.notOpened.message
        }
        guard AppLocation.shouldQuit(launched: launched.processIdentifier, current: getpid()) else {
            return AppLocation.MoveFailure.notOpened.message
        }
        NSApplication.shared.terminate(nil)
        return nil
    }
}
