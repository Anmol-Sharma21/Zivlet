import AppKit
import ZivletRuntime
import ZivletUI
import ZivletWheel
import ZivletWheelCore

extension AppDelegate {
    /// DEBUG: `-ZivletDemoWheel <mode>` shows the wheel without a drag; `-ZivletDemoConvert <path> <format>
    /// [-ZivletDemoCancelAfter <ms>]` runs the drop path for one file, and `-ZivletDemoAction <path> <action>
    /// [-ZivletDemoOption YES]` runs Copy, Copy Path or Terminal, so end-to-end checks need no drag.
    func launchDemoIfRequested() {
        #if DEBUG
            do {
                let arguments = ProcessInfo.processInfo.arguments
                if let scenario = try DemoScenario.parse(arguments: arguments) { wheel?.showDemo(scenario) }
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
