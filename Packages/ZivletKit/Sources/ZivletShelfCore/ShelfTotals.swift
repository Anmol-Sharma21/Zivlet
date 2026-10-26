/// Counts for a box's storage line (P2-142): items, known bytes, bytes of owned copies, and items whose size is not
/// known (folders, unreadable sizes), which are not guessed.
public struct ShelfTotals: Sendable, Equatable {
    public let count: Int
    public let bytes: Int64
    public let ownedBytes: Int64
    public let unknownSizes: Int

    public init(count: Int, bytes: Int64, ownedBytes: Int64, unknownSizes: Int) {
        self.count = count
        self.bytes = bytes
        self.ownedBytes = ownedBytes
        self.unknownSizes = unknownSizes
    }
}
