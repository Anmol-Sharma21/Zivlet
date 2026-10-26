import AppKit
import ZivletShelfCore

#if DEBUG
    /// Made-up boxes for the debug previews (D-M5b-20): names, sizes and statuses only, with type icons; no file is
    /// read and nothing is saved.
    public enum BoxPreview {
        static let names: [(String, Int64)] = [
            ("holiday.mov", 84_000_000), ("report.pdf", 2_100_000), ("photo.heic", 3_400_000), ("notes.txt", 4_000),
            ("song.m4a", 7_800_000), ("slides.key", 12_000_000), ("archive.zip", 41_000_000), ("logo.png", 180_000),
        ]

        public static func model(
            _ state: BoxShotFlags.State, finish: BoxFinish, maxHeight: CGFloat, icon: (String) -> NSImage
        ) -> BoxViewModel {
            let items = state == .empty ? [] : self.items(attention: state == .attention)
            let selected = Set(items.prefix(3).map(\.id))
            let selection: Set<UUID> = [.selection, .confirmTrash].contains(state) ? selected : []
            let presentation = BoxPresentation(
                base: base(state), overlay: overlay(state), dock: state == .docked ? .right : nil,
                missing: items.filter { !$0.isAvailable }.count, isEmpty: items.isEmpty)
            return BoxViewModel(
                items: items, selection: selection, presentation: presentation,
                viewMode: state == .list ? .list : .grid,
                finish: finish, images: Dictionary(uniqueKeysWithValues: items.map { ($0.id, icon($0.name)) }),
                maxHeight: maxHeight)
        }

        /// `Box: frame x y w h` in whole points, y from the top of the menu-bar display, as the island logs frames.
        public static func frameLine(_ frame: CGRect, screenTop: CGFloat) -> String {
            let values = [frame.minX, screenTop - frame.maxY, frame.width, frame.height].map { Int($0.rounded()) }
            return "Box: frame " + values.map(String.init).joined(separator: " ")
        }

        private static func items(attention: Bool) -> [BoxItemModel] {
            names.enumerated().map { index, entry in
                let path = "/Users/demo/Downloads/\(entry.0)"
                let status: ItemStatus
                switch (attention, index) {
                case (true, 1): status = .missing
                case (true, 4): status = .inTrash(path: "/Users/demo/.Trash/\(entry.0)")
                case (true, 6): status = .volumeOffline(name: "Backup")
                default: status = .present(path: path)
                }
                return BoxItemModel(id: UUID(), name: entry.0, bytes: entry.1, status: status)
            }
        }

        private static func base(_ state: BoxShotFlags.State) -> BoxPresentation.Base {
            switch state {
            case .hidden: .hidden
            case .docked: .docked(.right)
            case .collapsed: .collapsed
            default: .expanded
            }
        }

        private static func overlay(_ state: BoxShotFlags.State) -> BoxPresentation.Overlay? {
            switch state {
            case .dropTarget: .dropTarget(count: 3)
            case .busy: .busy(verb: "Moving 8 items", fraction: 0.4)
            case .confirmTrash: .confirm(.trash(count: 3))
            case .confirmClear: .confirm(.clear)
            default: nil
            }
        }
    }
#endif
