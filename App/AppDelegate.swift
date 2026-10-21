import AppKit
import ZivletCore
import ZivletRuntime
import ZivletTrigger
import ZivletTriggerHost
import ZivletWheel
import ZivletWheelCore
import os

/// Composition root only (02 ADR-02, 14 §3.1): builds the trigger host, the wheel, the conversion service, the result
/// HUD and the status menu, and wires them. A drop on a conversion slice starts a batch (05 P1-33).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Debug builds only: `-ZivletFlagsMonitor YES` adds the global `flagsChanged` monitor for spike P-T2 (off by
    /// default, 03a §1.8). Its permission behaviour is unknown, so Release never reads the default.
    static let flagsMonitorKey = "ZivletFlagsMonitor"
    /// "Reveal results in Finder" (03a §4.5), default on; `-ZivletRevealResults NO` turns it off.
    static let revealResultsKey = "ZivletRevealResults"
    static let quitLimit = Duration.seconds(2)

    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
    private let conversions = ConversionService.standard()
    private let undoHistory = UndoHistory()
    private let hud = ResultHUD()
    private var trigger: TriggerHost?
    private var wheel: WheelController?
    private var statusMenu: StatusMenu?
    #if DEBUG
        private let debugHUD = DebugHUD()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.revealResultsKey: true])
        reapOrphans()
        let reader = DragPayloadReader()
        let wheel = WheelController(reader: reader)
        let config = TriggerConfig()
        let trigger = TriggerHost(
            config: config,
            reader: SystemInputReader(pointerInsideWheel: { [weak wheel] in wheel?.isPointerInside ?? false }),
            scheduler: SystemTriggerScheduler(),
            listensToFlagsChanged: Self.debugFlagsMonitorEnabled(),
            probe: { count in await reader.summary(changeCount: count) })
        trigger.onWheelEffect = { [weak wheel] effect in wheel?.apply(effect) }
        wheel.onDragEnded = { [weak trigger] in trigger?.receive(.dropHandled) }
        wheel.delegate = self
        statusMenu = StatusMenu(bindings: config.bindings, wheel: wheel)
        self.wheel = wheel
        self.trigger = trigger
        trigger.start()
        wireHUD()
        observeConversions()
        ProcessInfo.processInfo.disableAutomaticTermination("Watching drag gestures")
        Task {
            wheel.capabilities = CapabilitySnapshot(unavailableTargets: await conversions.unavailableTargets())
            await wheel.prewarm()
            launchDemoIfRequested()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { trigger?.stop() }

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

    private func wireHUD() {
        hud.onCancel = { [conversions] batch in Task { await conversions.cancel(batch) } }
        hud.onReveal = { urls in NSWorkspace.shared.activateFileViewerSelecting(urls) }
        hud.onUndo = { [logger, undoHistory] batch in
            guard let result = await undoHistory.undo(batch) else {
                return UndoReply(message: "This can no longer be undone.", canRetry: false)
            }
            logger.notice("Undo: \(result.trashed.count) moved to the Trash, \(result.skipped.count) left in place")
            return UndoReply(message: result.message, canRetry: result.canRetry)
        }
    }

    private func observeConversions() {
        let snapshots = conversions.snapshots
        Task {
            for await snapshot in snapshots { self.present(snapshot) }
        }
    }

    private func present(_ snapshot: BatchSnapshot) {
        hud.show(snapshot)
        guard snapshot.isFinished else { return }
        logger.notice("Conversion finished: \(BatchPresentation.logLine(snapshot), privacy: .public)")
        for failure in snapshot.failures {
            let detail = String(describing: failure.error)  // may hold paths (stderr tail, folder): private
            logger.error(
                "Conversion failed: \(failure.name, privacy: .private): \(failure.error.logDescription, privacy: .public) \(detail, privacy: .private)"
            )
        }
        let published = snapshot.outputs
        if !published.isEmpty {
            Task { [undoHistory] in await undoHistory.record(snapshot.batch, outputs: published) }
        }
        let outputs = published.map(\.url)
        if !outputs.isEmpty, UserDefaults.standard.bool(forKey: Self.revealResultsKey) {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
    }

    /// The drop path, shared by real drops and the DEBUG demo.
    @discardableResult
    private func handle(_ selection: WheelSelection, near point: CGPoint?) -> Task<BatchID, Never>? {
        logger.notice("Wheel selection: \(selection.summary(), privacy: .public)")
        guard case .convert(let format) = selection.target else {
            #if DEBUG
                debugHUD.show(selection.summary())
            #endif
            return nil
        }
        hud.prepare(near: point)
        let urls = selection.urls
        return Task { [conversions] in await conversions.convert(urls, to: format) }
    }

    /// DEBUG: `-ZivletDemoWheel <mode>` shows the wheel without a drag; `-ZivletDemoConvert <path> <format>
    /// [-ZivletDemoCancelAfter <ms>]` runs the drop path for one file, so end-to-end checks need no drag.
    private func launchDemoIfRequested() {
        #if DEBUG
            do {
                let arguments = ProcessInfo.processInfo.arguments
                if let scenario = try DemoScenario.parse(arguments: arguments) { wheel?.showDemo(scenario) }
                if let demo = try DemoConversion.parse(arguments: arguments) { runDemo(demo) }
            } catch {
                logger.error("Demo arguments refused: \(String(describing: error), privacy: .private)")
            }
        #endif
    }

    #if DEBUG
        private func runDemo(_ demo: DemoConversion) {
            let selection = WheelSelection(mode: .convert, target: .convert(demo.target), urls: [demo.url])
            guard let started = handle(selection, near: nil), let delay = demo.cancelAfter else { return }
            Task { [conversions] in
                let batch = await started.value
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return  // only cancellation of this demo task ends the sleep early
                }
                await conversions.cancel(batch)
            }
        }
    #endif
}

extension AppDelegate: WheelControllerDelegate {
    func wheelController(_ controller: WheelController, didSelect selection: WheelSelection) {
        handle(selection, near: NSEvent.mouseLocation)
    }
}
