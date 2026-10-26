import AppKit
import ZivletShelfCore

@testable import ZivletBox

/// Made-up items for the view tests: names, sizes and statuses only, no files.
@MainActor
enum BoxViewFixtures {
    static func items(_ count: Int, missing: Int = 0) -> [BoxItemModel] {
        (0..<count).map { n in
            let status: ItemStatus = n < missing ? .missing : .present(path: "/Users/u/Downloads/file-\(n).png")
            return BoxItemModel(id: UUID(), name: "file-\(n).png", bytes: 1_000_000, status: status)
        }
    }

    static func model(
        _ items: [BoxItemModel], base: BoxPresentation.Base = .expanded, overlay: BoxPresentation.Overlay? = nil,
        mode: Shelf.ViewMode = .grid, selection: Set<UUID> = [], finish: BoxFinish = .solid
    ) -> BoxViewModel {
        let missing = items.filter { !$0.isAvailable }.count
        return BoxViewModel(
            items: items, selection: selection,
            presentation: BoxPresentation(
                base: base, overlay: overlay, missing: missing, isEmpty: items.isEmpty),
            viewMode: mode, finish: finish, maxHeight: 678)
    }
}
