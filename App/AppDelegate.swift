import AppKit
import ZivletActions
import ZivletBox
import ZivletCore
import ZivletRuntime
import ZivletSettings
import ZivletTrigger
import ZivletTriggerHost
import ZivletUI
import ZivletWheel
import ZivletWheelCore
import os

/// Composition root only (02 ADR-02, 14 §3.1): builds the trigger host, the wheel, the conversion service, the result
/// HUD, the notch island (one reader, one set of hosts, one Notch HUD), the actions, the Drop Box and the status menu,
/// and wires them. A drop on a conversion slice starts a batch (05 P1-33); a
/// drop on an action petal runs the action (P1-44, P1-45).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Debug builds only: `-ZivletFlagsMonitor YES` adds the global `flagsChanged` monitor for spike P-T2 (off by
    /// default, 03a §1.8). Its permission behaviour is unknown, so Release never reads the default.
    static let flagsMonitorKey = "ZivletFlagsMonitor"
    static let quitLimit = Duration.seconds(2)

    let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
    let conversions = ConversionService.standard()
    private let undoHistory = UndoHistory()
    let island = IslandWiring()
    lazy var conversion = ConversionWiring(
        conversions: conversions, undoHistory: undoHistory, menu: menu, notch: island.hud,
        revealsResults: { [weak self] in self?.settings.revealsResults ?? false },
        defaultRoute: { [weak self] in self?.defaultRoute ?? .nearDrop }
    ) { [weak self] batch in
        await self?.undo(batch) ?? UndoReply(message: "This can no longer be undone.", canRetry: false)
    }
    private lazy var settings = SettingsWiring(conversions: conversions)
    private let updater = UpdaterWiring()
    lazy var settingsWindow = SettingsWindowWiring(
        store: settings.store, conversions: conversions, displays: island.reader,
        checkForUpdates: updater.checkForUpdates, boxStorage: { [weak self] in self?.box.controller.storageBytes ?? 0 },
        emptyBoxStorage: { [weak self] in self?.box.controller.emptyStorage() }
    ) {
        [weak self] in self?.trigger?.trace.lines ?? []
    }
    lazy var box = BoxWiring(
        settings: { [weak self] in self?.settings.settings.box ?? BoxGroup() }, ports: boxPorts,
        actions: BoxActions(service: ActionService(undoHistory: undoHistory)))
    private lazy var actions = ActionWiring(
        undoHistory: undoHistory, notch: island.hud, route: { [weak self] in self?.defaultRoute ?? .nearDrop },
        box: box.adding, terminalID: { [weak self] in self?.settings.terminalID ?? "" }
    ) { [weak self] batch in
        await self?.undo(batch) ?? UndoReply(message: "This can no longer be undone.", canRetry: false)
    }
    private var trigger: TriggerHost?
    var wheel: WheelController?
    private lazy var menu = MenuWiring(settings: settings.store, undoHistory: undoHistory, island: island)
    private lazy var onboarding = OnboardingWiring(store: settings.store)
    private lazy var coach = CoachWiring(store: settings.store)
    #if DEBUG
        private let debugHUD = DebugHUD()
        private let boxFlags = BoxShots.flags()
        private var boxPreview: BoxPreviewPanel?
        private var dragTraces: DragTraceRecorder?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        ResourceLimits.raiseOpenFiles()
        reapOrphans()
        let reader = DragPayloadReader()
        let wheel = WheelController(
            reader: reader, feedback: settings.feedback,
            appearance: { [settings] in WheelAppearance.current(settings: settings.wheelTheme) })
        let config = settings.settings.trigger.config
        let trigger = TriggerHost(
            config: config,
            reader: SystemInputReader(pointerInsideWheel: { [weak wheel] in wheel?.isPointerInside ?? false }),
            scheduler: SystemTriggerScheduler(),
            listensToFlagsChanged: Self.debugFlagsMonitorEnabled(),
            probe: { count in await reader.summary(changeCount: count) })
        trigger.onWheelEffect = { [weak wheel, coach, island, box] effect in
            guard let wheel else { return }
            island.wheel(effect)
            box.wheel(effect)
            wheel.apply(effect)
            coach.observe(effect, wheel: wheel)
        }
        wheel.onDragEnded = { [weak trigger] in trigger?.receive(.dropHandled) }
        wheel.delegate = self
        updater.start(with: settings.settings.updates)
        settings.updater = updater
        wireMenu(wheel)
        self.wheel = wheel
        self.trigger = trigger
        settings.attach(trigger)
        #if DEBUG
            dragTraces = DragTraceRecording.start(trigger: trigger, displays: island.reader)
        #endif
        conversion.start()
        startBox(trigger)
        ProcessInfo.processInfo.disableAutomaticTermination("Watching drag gestures")
        Task {
            wheel.capabilities = CapabilitySnapshot(
                unavailableTargets: await conversions.unavailableTargets(),
                unavailableActions: ActionWiring.unavailableActions)
            await wheel.prewarm()
            launchDemoIfRequested()
            onboarding.showIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trigger?.stop()
        box.quit()
    }

    /// The Drop Box: results go where the placement says; the panel comes back as it was (P2-55 §9.5); the notch
    /// tray joins the island and the trigger's live samples (P2-143).
    private func startBox(_ trigger: TriggerHost) {
        box.present = { [weak self] result, point in
            self?.actions.present(result, near: point)
            self?.menu.refreshRecent()  // a Move or Copy to… from the box adds to Recent Results
        }
        box.start()
        box.startTray(island: island, trigger: trigger)
        #if DEBUG
            boxPreview = BoxShots.run(
                boxFlags, controller: box.controller, finish: BoxFinish.resolve(island.finishSettingsNow))
        #endif
    }

    /// The standard stores; Debug demos and previews use their own (D-M5b-20).
    private var boxPorts: BoxPorts {
        #if DEBUG
            BoxShots.ports(boxFlags)
        #else
            BoxPorts.standard()
        #endif
    }

    /// Opening Zivlet again while it runs (Finder, Spotlight) opens Settings (03b §8.3).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    /// Quit (03a §4.2): cancel running jobs, wait up to 2 s for their cleanup, then let AppKit terminate.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let stopped = await conversions.shutdown(within: Self.quitLimit)
            if !stopped { logger.error("Quit: jobs still stopping after 2 s; the orphan reaper cleans up next launch") }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Always false in Release, so no shipped build can install a key-class global monitor (no TCC prompt).
    private static func debugFlagsMonitorEnabled() -> Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: flagsMonitorKey)
        #else
            false
        #endif
    }

    private func reapOrphans() {
        let report = OrphanReaper().reap()
        if report.killed + report.removedFiles > 0 {
            logger.notice("Cleaned up after a previous crash: \(report.killed) helpers, \(report.removedFiles) files")
        }
    }

    private func wireMenu(_ wheel: WheelController) {
        menu.handlers = MenuHandlers(
            cancel: { [conversions] batch in Task { await conversions.cancel(batch) } },
            undo: { [weak self] batch in
                Task {
                    guard let self else { return }
                    self.actions.announce(await self.undo(batch).message)
                }
            },
            settings: { [weak self] in self?.settingsWindow.show() },
            practice: { [weak self] in self?.onboarding.show(.practiceConvert) },
            showDropBox: { [weak self] in self?.box.show() },
            checkForUpdates: updater.checkForUpdates)
        menu.install(wheel: wheel)
        actions.onFinished = { [menu] in menu.refreshRecent() }
    }

    /// The presenter a new batch or action goes to (D-M5a-2): the override or the setting, resolved for this Mac, and
    /// near the drop while the island has no display to draw on.
    private var defaultRoute: HUDRoute {
        settings.defaultRoute(hasBuiltInNotch: island.hasBuiltInNotch).usable(islandHasDisplay: island.canShow)
    }

    /// Undo for conversions, Moves, copies and the Drop Box's Clear alike; the reply is the sentence the HUD shows.
    private func undo(_ batch: BatchID) async -> UndoReply {
        if box.controller.undoClear(batch) { return UndoReply(message: BoxWiring.restoredMessage, canRetry: false) }
        guard let result = await undoHistory.undo(batch) else {
            return UndoReply(message: "This can no longer be undone.", canRetry: false)
        }
        logger.notice(
            "Undo: \(result.trashed.count) trashed, \(result.restored.count) moved back, \(result.skipped.count) left in place"
        )
        menu.refreshRecent()
        return UndoReply(message: result.message, canRetry: result.canRetry, removed: result.trashed)
    }

    /// The drop path, shared by real drops and the DEBUG demo.
    @discardableResult
    func handle(_ selection: WheelSelection, near point: CGPoint?) -> Task<BatchID, Never>? {
        logger.notice("Wheel selection: \(selection.summary(), privacy: .public)")
        if onboarding.receive(selection) { return nil }
        if case .action(let action) = selection.target {
            actions.run(action, urls: selection.urls, optionHeld: selection.optionHeld, near: point)
            return nil
        }
        guard case .convert(let format) = selection.target else {
            #if DEBUG
                debugHUD.show(selection.summary())
            #endif
            return nil
        }
        return conversion.convert(selection.urls, to: format, near: point)
    }
}

extension AppDelegate: WheelControllerDelegate {
    func wheelController(_ controller: WheelController, didSelect selection: WheelSelection) {
        handle(selection, near: NSEvent.mouseLocation)
    }
}
