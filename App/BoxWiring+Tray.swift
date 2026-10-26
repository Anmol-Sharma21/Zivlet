import AppKit
import ZivletBox
import ZivletNotch
import ZivletTrigger
import ZivletTriggerHost

/// The notch tray in the app (P2-143, D-M5b-16): the tray registers with the island's one set of hosts (D-M5a-9) and
/// rests on the box's changes; the driver rides on the trigger host's live samples, so Pause stops it with the rest.
/// Zones follow the island's display reader. Settings › Drop Box decide the drop target and the shake.
extension BoxWiring {
    func startTray(island: IslandWiring, trigger: TriggerHost) {
        #if DEBUG
            if let state = previewFlags.trayPreview { return startTrayPreview(state, island: island) }
        #endif
        let tray = TrayClient(
            hosts: island.hosts, box: controller,
            opensWhileDragging: { [settings] in settings().trayWhileDragging })
        island.hosts.register(tray, as: .tray)
        let driver = TrayDriver(
            tray: tray, zones: TrayDriver.zones(for: island.reader.displays),
            shakeToOpen: { [settings] in settings().shakeToOpen },
            openForShake: { [weak controller] point in controller?.showPanel(.point(point)) },
            itemCount: { _ in NSPasteboard(name: .drag).pasteboardItems?.count ?? 0 })
        let previousSample = trigger.onLiveSample
        trigger.onLiveSample = { [weak driver] sample in
            previousSample(sample)
            driver?.observe(sample)
        }
        let previousEnd = trigger.onDragEnded
        trigger.onDragEnded = { [weak driver] in
            previousEnd()
            driver?.dragEnded()
        }
        let previousChange = controller.onChange
        controller.onChange = { [weak tray] in
            previousChange()
            tray?.boxChanged()
        }
        let changes = island.reader.changes
        zoneWatch = Task { [weak driver] in
            for await displays in changes { driver?.zonesChanged(TrayDriver.zones(for: displays)) }
        }
        tray.boxChanged()
        self.tray = tray
        self.driver = driver
    }

    /// The wheel's effects as the trigger sends them: the tray steps aside while the wheel shows (D-M5b-8).
    func wheel(_ effect: TriggerEffect) {
        switch effect {
        case .show: driver?.wheelShown()
        case .hide: driver?.wheelHidden()
        default: break
        }
    }

    #if DEBUG
        /// `-ZivletTrayPreview <state>`: one tray state over a made-up box on the menu-bar display; no drag, no
        /// keyboard, and the toast stays. The island logs `Island: <surface>` and its frame for the capture script.
        private func startTrayPreview(_ state: BoxShotFlags.TrayState, island: IslandWiring) {
            let box = TrayPreviewBox { [controller] name in controller.placeholder(forName: name) }
            let tray = TrayClient(
                hosts: island.hosts, box: box, opensWhileDragging: { true },
                linger: { _ in try? await Task.sleep(for: .seconds(3_600)) })
            island.hosts.register(tray, as: .tray)
            guard let display = island.hosts.displayIDs.first else {
                return Self.logger.error("Tray preview: no display")
            }
            tray.preview(state, on: display)
            Self.logger.notice("Tray: \(state.rawValue, privacy: .public)")
            previewBox = box
            self.tray = tray
        }
    #endif
}
