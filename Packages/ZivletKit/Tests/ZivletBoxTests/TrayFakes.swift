import AppKit
import NotchTestSupport
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletShelfCore

@testable import ZivletBox

/// A box with `count` made-up items of 1 MB; it records what the tray asks of it.
final class FakeTrayBox: TrayBox {
    var count: Int
    var nextAdd = TrayAdded(outcome: AddOutcome(added: 0), ids: [])
    private(set) var drops = 0
    private(set) var undone: [[UUID]] = []
    private(set) var panels: [BoxAnchor] = []
    private(set) var presses: [BoxPress] = []

    init(count: Int) { self.count = count }

    var trayModel: BoxViewModel {
        let items = (0..<count).map { index in
            BoxItemModel(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(),
                name: "item \(index).png", bytes: 1_000_000, status: nil)
        }
        return BoxViewModel(
            items: items, selection: [], presentation: BoxPresentation(), viewMode: .grid, finish: .solid,
            maxHeight: 600)
    }

    func addDrop(_ pasteboard: NSPasteboard) async -> TrayAdded {
        drops += 1
        count += nextAdd.ids.count
        return nextAdd
    }

    func undoAdd(_ ids: [UUID]) {
        undone.append(ids)
        count -= ids.count
    }

    func showPanel(_ anchor: BoxAnchor) { panels.append(anchor) }
    func press(_ press: BoxPress) { presses.append(press) }
}

/// The app's one `IslandHosts` on the off-screen notch display (1) and plain display (2), a fake box and the tray
/// registered as `.tray`, at rest.
final class TrayRig {
    let hosts: IslandHosts
    let box: FakeTrayBox
    let tray: TrayClient
    var opensWhileDragging = true

    init(boxItems: Int) throws {
        hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        box = FakeTrayBox(count: boxItems)
        var rig: TrayRig?
        tray = TrayClient(hosts: hosts, box: box) { rig?.opensWhileDragging ?? true }
        rig = self
        hosts.register(tray, as: .tray)
        tray.boxChanged()
    }

    isolated deinit { hosts.close() }
}
