import ZivletShelfCore

/// What one drop gave the box (P2-141): the new items, the refused ones as "name: reason" lines for the action card
/// (never logged), and the bytes of the copies the box now owns.
public struct IntakeResult: Equatable {
    /// The refusal when nothing in the drop could be added (19c §4.2).
    public static let nothingUsable = "Only items stored on this Mac can be added"

    public let items: [ShelfItem]
    public let rejected: [String]
    public let ownedBytes: Int64

    public init(items: [ShelfItem], rejected: [String], ownedBytes: Int64) {
        self.items = items
        self.rejected = rejected
        self.ownedBytes = ownedBytes
    }
}
