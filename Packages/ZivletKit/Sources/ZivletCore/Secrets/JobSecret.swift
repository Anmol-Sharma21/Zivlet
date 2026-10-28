import Foundation

/// A password one job needs (P2-102, plan 20c B1, D-M7-14). The bytes live in one allocation of its own, which
/// `wipe()` and `deinit` overwrite with zeros through `memset_s` (the compiler may not drop it). Every description,
/// the mirror and string interpolation show `<password>`, without the bytes or their length. It is not `Codable`, so
/// no settings, history, job-record or diagnostics encoder can take one, and a type holding one cannot gain
/// synthesised `Codable` by accident; only `ZivletIPC` reads the bytes (`withBytes`, package access) to put them on the
/// worker's wire for their one job. Two secrets are equal only when they are the same object.
///
/// Best effort, as 17b §2.2 says: the `String` a text field produced and the buffers of XPC and the PDF library are
/// freed without being zeroed, and Swift gives no way to reach them (G-M7-5).
public final class JobSecret: @unchecked Sendable {
    /// What every description of a secret says.
    public static let redacted = "<password>"

    /// The secret's own allocation (one byte at least, so it is never empty) and how many of its bytes are held.
    private let allocation: UnsafeMutableRawBufferPointer
    private let count: Int
    private let lock = NSLock()
    private var wiped = false

    /// The UTF-8 bytes of `text`, copied into the secret's own buffer.
    public convenience init(utf8 text: String) {
        self.init(bytes: text.utf8)
    }

    public init<Bytes: Collection>(bytes: Bytes) where Bytes.Element == UInt8 {
        count = bytes.count
        allocation = UnsafeMutableRawBufferPointer.allocate(byteCount: max(1, count), alignment: 1)
        allocation.initializeMemory(as: UInt8.self, repeating: 0)
        allocation.copyBytes(from: bytes)
    }

    deinit {
        Self.zero(allocation)
        allocation.deallocate()
    }

    /// No bytes at all (an empty field).
    public var isEmpty: Bool { count == 0 }

    /// `wipe()` ran: the bytes are all zero now.
    public var isWiped: Bool {
        lock.withLock { wiped }
    }

    /// Overwrites the bytes with zeros in place. The secret stays allocated (and reads as zeros) until it is freed.
    public func wipe() {
        lock.withLock {
            Self.zero(allocation)
            wiped = true
        }
    }

    /// Lends the bytes for the length of `body`; for `ZivletIPC`'s wire form and the tests only.
    package func withBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(UnsafeRawBufferPointer(rebasing: allocation[0..<count])) }
    }

    private static func zero(_ memory: UnsafeMutableRawBufferPointer) {
        guard let base = memory.baseAddress, !memory.isEmpty else { return }
        _ = memset_s(base, memory.count, 0, memory.count)
    }
}

extension JobSecret: Equatable {
    public static func == (lhs: JobSecret, rhs: JobSecret) -> Bool { lhs === rhs }
}

extension JobSecret: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { Self.redacted }
    public var debugDescription: String { Self.redacted }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
