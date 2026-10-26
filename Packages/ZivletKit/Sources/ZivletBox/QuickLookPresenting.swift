import AppKit
import Quartz

/// Shows Quick Look for box items (17e §2.3 Space). The system presenter is `QLPreviewPanel`; tests use a fake.
public protocol QuickLookPresenting {
    func preview(_ urls: [URL])
}

/// `QLPreviewPanel` with the box as its data source. Opening it from the non-activating panel is a QA row (B9):
/// the prototypes did not try it.
public final class SystemQuickLook: NSObject, QuickLookPresenting, QLPreviewPanelDataSource {
    private var urls: [URL] = []

    override public init() { super.init() }

    public func preview(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }
}
