import AppKit
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger

/// The Drop Box's client of the island (P2-143, design/19 §8, NB6). During a file drag that rests at the notch it
/// asks for a drop target on that display; when the drag leaves or ends it goes back to rest: a sensor over the
/// housing on notch displays while the box has items (D-M5b-17), else nothing. The wheel wins (D-M5b-8): while it
/// shows, the tray rests and ignores the drag, and only a new approach after the wheel hides opens it again.
/// Before a drop it reads the drag's types and item count only (D-M5b-4).
public final class TrayClient {
    public static let label = "Drop Box"

    let hosts: IslandHosts
    let box: any TrayBox
    /// Settings › Drop Box › "Open at the notch while dragging".
    let opensWhileDragging: () -> Bool
    /// The drop target's display and the drag's item count, while it shows.
    var dropTarget: (display: UInt32, count: Int)?
    private(set) var wheelShowing = false

    public init(hosts: IslandHosts, box: any TrayBox, opensWhileDragging: @escaping () -> Bool) {
        self.hosts = hosts
        self.box = box
        self.opensWhileDragging = opensWhileDragging
    }

    /// The proximity rule's events during a live file drag, with the drag pasteboard's item count.
    public func proximity(_ event: NotchProximityEvent, itemCount: Int) {
        switch event {
        case .entered(let display):
            guard !wheelShowing, opensWhileDragging(), hosts.displayIDs.contains(display) else { return }
            open(on: display, count: itemCount)
        case .left(let display):
            guard dropTarget?.display == display else { return }
            close()
        }
    }

    /// The drag ended (dropped elsewhere or cancelled): back to rest.
    public func dragEnded() {
        guard dropTarget != nil else { return }
        close()
    }

    /// The wheel wins: back to rest at once, and the drag is ignored until it hides.
    public func wheelShown() {
        wheelShowing = true
        if dropTarget != nil { close() }
    }

    public func wheelHidden() { wheelShowing = false }

    /// The box's items changed: the rest follows (a sensor while there are items), and open content is redrawn.
    public func boxChanged() {
        rest()
        for display in hosts.displayIDs where hosts.activeClient(on: display) == .tray {
            hosts.contentChanged(on: display)
            hosts.accessibilityChanged(on: display)
        }
    }

    /// Puts every display at rest: a sensor on notch displays while the box has items, no request elsewhere. The
    /// display showing the drop target keeps it.
    func rest() {
        let hasItems = !box.trayModel.items.isEmpty
        for display in hosts.displayIDs where display != dropTarget?.display {
            guard hasItems, let geometry = hosts.display(display), NotchGeometry.hasNotch(geometry) else {
                hosts.withdraw(.tray, on: display)
                continue
            }
            hosts.request(Self.sensor(on: display), from: .tray)
        }
    }

    private func open(on display: UInt32, count: Int) {
        if let previous = dropTarget?.display, previous != display { close() }
        let opening = dropTarget == nil
        dropTarget = (display, count)
        hosts.request(Self.drop(on: display), from: .tray)
        hosts.contentChanged(on: display)
        if opening { hosts.announce(BoxSpeech.dropTarget(count), highPriority: false) }
    }

    func close() {
        dropTarget = nil
        rest()
    }

    static func sensor(on display: UInt32) -> IslandRequest {
        IslandRequest(client: .tray, display: display, resting: .sensor, hoverSurface: .expanded)
    }

    static func drop(on display: UInt32) -> IslandRequest {
        IslandRequest(client: .tray, display: display, resting: .dropTarget, hoverSurface: .dropTarget)
    }
}
