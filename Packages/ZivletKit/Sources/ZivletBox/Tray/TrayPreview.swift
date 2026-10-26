import AppKit
import ZivletActions
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger

#if DEBUG
    /// A made-up box for the tray's debug previews (D-M5b-20): the panel previews' names and sizes, type icons, no
    /// file read and nothing saved. Presses and drops do nothing.
    public final class TrayPreviewBox: TrayBox {
        private let icon: (String) -> NSImage

        public init(icon: @escaping (String) -> NSImage) { self.icon = icon }

        public var trayModel: BoxViewModel {
            BoxPreview.model(.grid, finish: .glass, maxHeight: 600, icon: icon)
        }

        public var trayCount: Int { trayModel.items.count }
        public var trayBytes: Int64 { trayModel.totalBytes }
        public func prepareTray(redraw: @escaping () -> Void) {}
        public func report(_ result: ActionResult) {}

        public func addDrop(_ pasteboard: NSPasteboard) async -> TrayAdded {
            TrayAdded(outcome: AddOutcome(added: 0), ids: [])
        }

        public func undoAdd(_ ids: [UUID]) {}
        public func showPanel(_ anchor: BoxAnchor) {}
        public func press(_ press: BoxPress) {}
    }

    extension TrayClient {
        /// Shows one tray state on `display` for a screenshot, without a drag and without taking the keyboard.
        public func preview(_ state: BoxShotFlags.TrayState, on display: UInt32) {
            switch state {
            case .dropTarget:
                proximity(.entered(display: display), itemCount: 3)
            case .toast:
                lastToast = TrayToastModel(
                    display: display, text: BoxCopy.added(3), spoken: BoxSpeech.added(3), failed: false,
                    undoIDs: [UUID(), UUID(), UUID()])
                hosts.request(
                    IslandRequest(client: .tray, display: display, resting: .toast, hoverSurface: .expanded),
                    from: .tray)
                hosts.contentChanged(on: display)
            case .compact:
                hosts.request(
                    IslandRequest(client: .tray, display: display, resting: .expanded, hoverSurface: .expanded),
                    from: .tray)
                hosts.contentChanged(on: display)
            case .sensor:
                boxChanged()
            }
        }
    }
#endif
