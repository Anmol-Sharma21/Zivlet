import AppKit
import ZivletCore
import ZivletTrigger

/// Real OS reads for one sample (03a §1.2). Every read is permission-free: modifier flags, button state, the drag
/// pasteboard's change count and type list, and the global mouse location. No key codes, no URL reads.
public final class SystemInputReader: InputReading {
    /// File URLs plus every file-promise type (Mail, Photos, browsers).
    public static let fileTypes: [NSPasteboard.PasteboardType] =
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    private let pasteboard: NSPasteboard
    private let insideWheel: () -> Bool
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag), pointerInsideWheel: @escaping () -> Bool = { false }
    ) {
        self.pasteboard = pasteboard
        insideWheel = pointerInsideWheel
        origin = clock.now
    }

    public var uptime: Duration { clock.now - origin }
    public var modifiers: ModifierMask { ModifierMask(NSEvent.modifierFlags) }
    public var primaryButtonDown: Bool { NSEvent.pressedMouseButtons & 1 == 1 }
    public var dragChangeCount: Int { pasteboard.changeCount }
    public var location: Point2D { Point2D(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y) }
    public var pointerInsideWheel: Bool { insideWheel() }

    public func dragHasFileTypes() -> Bool { pasteboard.availableType(from: Self.fileTypes) != nil }
}
