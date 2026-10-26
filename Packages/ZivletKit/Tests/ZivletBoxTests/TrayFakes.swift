import AppKit
import NotchTestSupport
import ZivletActions
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
    private(set) var prepared = 0
    private(set) var reported: [ActionResult] = []

    init(count: Int) { self.count = count }

    var trayCount: Int { count }
    var trayBytes: Int64 { Int64(count) * 1_000_000 }
    func prepareTray(redraw: @escaping () -> Void) { prepared += 1 }
    func report(_ result: ActionResult) { reported.append(result) }

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

/// The app's one `IslandHosts` on the off-screen notch display (1) and plain display (2), a box (a fake unless one
/// is given) and the tray registered as `.tray`, at rest. Toast lingers are recorded and end at once.
final class TrayRig {
    let hosts: IslandHosts
    let box: FakeTrayBox
    let tray: TrayClient
    var opensWhileDragging = true
    /// Holds each toast's linger until `releaseLingers()`, for tests that read the toast after an async drop.
    var holdsLingers = false
    private var heldLingers: [CheckedContinuation<Void, Never>] = []
    private(set) var lingers: [Duration] = []
    private(set) var surfaces: [(UInt32, IslandSurface)] = []

    convenience init(boxItems: Int) throws {
        try self.init(fake: FakeTrayBox(count: boxItems), box: nil)
    }

    /// A rig over a real box (the controller); `box` (the fake) is then unused.
    convenience init(box real: any TrayBox) throws {
        try self.init(fake: FakeTrayBox(count: 0), box: real)
    }

    private init(fake: FakeTrayBox, box real: (any TrayBox)?) throws {
        hosts = IslandHosts(
            provider: try FakeDisplayProvider.notchAndExternal(), clock: ManualClock(), animation: .instant)
        box = fake
        var rig: TrayRig?
        tray = TrayClient(
            hosts: hosts, box: real ?? fake, opensWhileDragging: { rig?.opensWhileDragging ?? true },
            linger: { duration in
                rig?.lingers.append(duration)
                guard rig?.holdsLingers == true else { return }
                await withCheckedContinuation { rig?.heldLingers.append($0) }
            })
        rig = self
        hosts.onSurface = { display, surface, _ in rig?.surfaces.append((display, surface)) }
        hosts.register(tray, as: .tray)
        tray.boxChanged()
    }

    /// Surfaces shown on `display`, in order.
    func shown(on display: UInt32) -> [IslandSurface] { surfaces.filter { $0.0 == display }.map(\.1) }

    /// Ends the held lingers; a linger that starts later is not held, so a release that comes first is not lost.
    func releaseLingers() {
        holdsLingers = false
        heldLingers.forEach { $0.resume() }
        heldLingers = []
    }

    isolated deinit {
        releaseLingers()
        hosts.close()
    }
}
