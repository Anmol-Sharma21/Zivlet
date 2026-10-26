import AppKit

/// The system share picker behind a port, so the Drop Box's Share is tested without a popover (P2-142).
public protocol SharePicking: AnyObject {
    /// Shows the picker for `urls`, pointing at `rect` in `view`'s coordinates from `edge`.
    func show(_ urls: [URL], relativeTo rect: CGRect, of view: NSView, edge: NSRectEdge)
}

/// `NSSharingServicePicker(items:)` with a delegate. It is held from `show` until the person picks a service or
/// dismisses it, as the system keeps no strong reference. The system reports nothing useful about the share itself,
/// so no toast follows (prototype: AirDrop is the picker's own row; Mail, Messages and the rest finish in their
/// apps). The deprecated `NSSharingService.sharingServices(forItems:)` is not used.
public final class SystemSharePicker: NSObject, SharePicking, NSSharingServicePickerDelegate {
    private var picker: NSSharingServicePicker?

    override public init() { super.init() }

    /// A picker is on screen.
    var isShowing: Bool { picker != nil }

    public func show(_ urls: [URL], relativeTo rect: CGRect, of view: NSView, edge: NSRectEdge) {
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        hold(picker)
        picker.show(relativeTo: rect, of: view, preferredEdge: edge)
    }

    func hold(_ picker: NSSharingServicePicker) {
        picker.delegate = self
        self.picker = picker
    }

    public func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        picker = nil
    }
}
