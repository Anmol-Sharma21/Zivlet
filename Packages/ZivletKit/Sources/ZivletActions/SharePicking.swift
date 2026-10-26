import AppKit
import os

/// The system share picker behind a port, so the Drop Box's Share is tested without a popover (P2-142).
public protocol SharePicking: AnyObject {
    /// Runs when the chosen service says it could not share the items.
    var onFailure: () -> Void { get set }
    /// Shows the picker for `urls`, pointing at `rect` in `view`'s coordinates from `edge`.
    func show(_ urls: [URL], relativeTo rect: CGRect, of view: NSView, edge: NSRectEdge)
}

/// `NSSharingServicePicker(items:)` with a delegate. It is held from `show` until the person picks a service or
/// dismisses it, as the system keeps no strong reference. The system reports nothing useful about a share that
/// works, so no toast follows (prototype: AirDrop is the picker's own row; Mail, Messages and the rest finish in
/// their apps); a service that reports a failure calls `onFailure`, and its error is logged by domain and code. The
/// deprecated `NSSharingService.sharingServices(forItems:)` is not used.
public final class SystemSharePicker: NSObject, SharePicking, NSSharingServicePickerDelegate,
    NSSharingServiceDelegate
{
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")

    private var picker: NSSharingServicePicker?
    public var onFailure: () -> Void = {}

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

    public func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService
    ) -> (any NSSharingServiceDelegate)? { self }

    public func sharingService(
        _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error
    ) {
        let error = error as NSError
        Self.logger.error("Share failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
        onFailure()
    }
}
