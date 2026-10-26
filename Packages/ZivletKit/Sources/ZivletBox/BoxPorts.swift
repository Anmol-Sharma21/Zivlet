import AppKit
import ZivletCore
import ZivletNotchCore
import ZivletShelfCore

/// Everything the controller reads or writes outside itself, so tests replace each with a fake or a temporary
/// folder.
public struct BoxPorts {
    public let store: BoxStore
    public let storage: OwnedStorage
    public let maker: any BookmarkMaking
    public let resolver: any BookmarkResolving
    public let isMounted: (String) -> Bool
    public let promises: any PromiseReceiving
    public let thumbnails: any ThumbnailMaking
    public let quickLook: any QuickLookPresenting
    /// The displays' visible frames, the menu-bar display first.
    public let visibleFrames: () -> [Rect2D]
    public let finish: () -> BoxFinish
    public let now: () -> Date
    /// Seconds on a monotonic clock, for type-to-select.
    public let uptime: () -> Double

    public init(
        store: BoxStore, storage: OwnedStorage, maker: any BookmarkMaking, resolver: any BookmarkResolving,
        isMounted: @escaping (String) -> Bool, promises: any PromiseReceiving, thumbnails: any ThumbnailMaking,
        quickLook: any QuickLookPresenting, visibleFrames: @escaping () -> [Rect2D], finish: @escaping () -> BoxFinish,
        now: @escaping () -> Date = Date.init, uptime: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.store = store
        self.storage = storage
        self.maker = maker
        self.resolver = resolver
        self.isMounted = isMounted
        self.promises = promises
        self.thumbnails = thumbnails
        self.quickLook = quickLook
        self.visibleFrames = visibleFrames
        self.finish = finish
        self.now = now
        self.uptime = uptime
    }

    /// The same ports over another store and storage (the debug demo keeps its box away from `boxes.json`).
    public func with(store: BoxStore, storage: OwnedStorage) -> BoxPorts {
        BoxPorts(
            store: store, storage: storage, maker: maker, resolver: resolver, isMounted: isMounted, promises: promises,
            thumbnails: thumbnails, quickLook: quickLook, visibleFrames: visibleFrames, finish: finish, now: now,
            uptime: uptime)
    }

    /// The real stores and system ports: `boxes.json` and `Box/` in Application Support, Foundation bookmarks
    /// (never security-scoped), Quick Look, the screens' visible frames and the accessibility display options.
    public static func standard() -> BoxPorts {
        let bookmarks = SystemBookmarks()
        return BoxPorts(
            store: .standard(), storage: .standard(), maker: bookmarks, resolver: bookmarks,
            isMounted: SystemBookmarks.isMounted, promises: SystemPromiseReceiver(),
            thumbnails: SystemThumbnailMaker(), quickLook: SystemQuickLook(),
            visibleFrames: { NSScreen.screens.map { Rect2D($0.visibleFrame) } },
            finish: {
                let workspace = NSWorkspace.shared
                return BoxFinish.resolve(
                    .init(
                        reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                        increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast))
            })
    }
}

/// Where the panel opens (19c §4.4).
public enum BoxAnchor: Sendable, Equatable {
    /// Its saved frame or dock edge; the first time, against the right edge of the menu-bar display.
    case saved
    /// The BOX slice's drop point or the pointer (shake), clamped inside the visible frame.
    case point(Point2D)
    /// Below the island, centred on it (open from the tray).
    case below(Rect2D)
}

/// What adding to the box did, for the toast and the card (19c §5).
public struct AddOutcome: Sendable, Equatable {
    public let added: Int
    public let duplicates: [String]
    /// "name: reason" lines for the action card.
    public let rejected: [String]
    /// Why nothing could be added, in Zivlet's words; nil when something was.
    public let failure: String?

    public init(added: Int, duplicates: [String] = [], rejected: [String] = [], failure: String? = nil) {
        self.added = added
        self.duplicates = duplicates
        self.rejected = rejected
        self.failure = failure
    }

    /// "Added 3", or nil when nothing was added.
    public var toast: String? { added > 0 ? BoxCopy.added(added) : nil }
}
