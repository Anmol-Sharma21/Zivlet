import AppKit
import ZivletRuntime
import ZivletUI
import ZivletWheel
import ZivletWheelCore

extension AppDelegate {
    /// DEBUG: `-ZivletDemoWheel <mode> [-ZivletDemoRepeat <n>]` shows the wheel without a drag (n times); `-ZivletDemoConvert <path> <format>
    /// [-ZivletDemoCancelAfter <ms>]` runs the drop path for one file, and `-ZivletDemoAction <path> <action>
    /// [-ZivletDemoOption YES]` runs Copy, Copy Path or Terminal, and `-ZivletIslandPreview <state>` puts a made-up
    /// job on the notch island, so end-to-end checks need no drag. The island preview alone also exists in the CPU
    /// measurement build (`ZIVLET_ISLAND_PREVIEW`, D-ND3); a shipped Release build has none of these.
    func launchDemoIfRequested() {
        #if DEBUG
            do {
                let arguments = ProcessInfo.processInfo.arguments
                if let scenario = try DemoScenario.parse(arguments: arguments) { showDemo(scenario) }
                if let pane = SettingsPane.demo(arguments: arguments) { settingsWindow.show(pane) }
                if let dir = UITestFixture.directory(arguments: arguments) {
                    conversion.hud.show(try UITestFixture.snapshot(in: dir))
                }
                if let demo = try DemoConversion.parse(arguments: arguments) { runDemo(demo) }
                if let demo = try DemoAction.parse(arguments: arguments) {
                    let selection = WheelSelection(
                        mode: .actions, target: .action(demo.action), urls: [demo.url], optionHeld: demo.optionHeld)
                    handle(selection, near: nil)
                }
            } catch {
                logger.error("Demo arguments refused: \(String(describing: error), privacy: .private)")
            }
        #endif
        launchIslandPreviewIfRequested()
    }

    #if DEBUG || ZIVLET_ISLAND_PREVIEW
        private func launchIslandPreviewIfRequested() {
            do {
                if let preview = try IslandPreview.parse(arguments: ProcessInfo.processInfo.arguments) {
                    try runIslandPreview(preview)
                }
            } catch {
                logger.error("Island preview refused: \(String(describing: error), privacy: .private)")
            }
        }

        /// Shows the preview's jobs (or its action) on the Notch HUD, opens its card after a second when the state
        /// asks, and feeds `.progress` a new snapshot ten times a second until the app quits.
        private func runIslandPreview(_ preview: IslandPreview) throws {
            let hud = island.hud
            let snapshots = try preview.snapshots()
            logger.notice("Island preview: \(preview.rawValue, privacy: .public)")
            for snapshot in snapshots {
                hud.prepare(near: nil)
                hud.show(snapshot)
            }
            if let action = preview.action { hud.show(action, near: nil) }
            if preview.opens {
                Task { [island] in
                    guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
                    island.hosts.expandRequested()
                }
            }
            guard let tick = preview.tick, let first = snapshots.first else { return }
            Task { [logger] in
                var step = 0
                while (try? await Task.sleep(for: tick)) != nil {
                    step += 1
                    do {
                        hud.show(try preview.advanced(first, step: step))
                    } catch {
                        return logger.error("Island preview stopped: \(String(describing: error), privacy: .private)")
                    }
                }
            }
        }
    #else
        private func launchIslandPreviewIfRequested() {}
    #endif

    #if DEBUG
        /// Shows the demo wheel `repeats` times, 200 ms shown and 200 ms hidden each, for the bench (P1-63).
        private func showDemo(_ scenario: DemoScenario) {
            guard scenario.repeats > 1 else {
                wheel?.showDemo(scenario)
                return
            }
            Task { [weak self] in
                let gap = Duration.milliseconds(200)
                for index in 0..<scenario.repeats {
                    if index > 0 {
                        self?.wheel?.hide()
                        guard (try? await Task.sleep(for: gap)) != nil else { return }  // cancelled: stop
                    }
                    self?.wheel?.showDemo(scenario)
                    guard (try? await Task.sleep(for: gap)) != nil else { return }
                }
            }
        }

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
