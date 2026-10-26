import Foundation

/// What happened to the items of one drop (P2-141): the ids that were added, and the names of the items that were
/// already in the box or did not fit under its cap. Names, so a toast can say which; never logged.
public struct AddReport: Sendable, Equatable {
    public let added: [UUID]
    public let duplicates: [String]
    public let overCap: [String]

    public init(added: [UUID] = [], duplicates: [String] = [], overCap: [String] = []) {
        self.added = added
        self.duplicates = duplicates
        self.overCap = overCap
    }

    public var isEverythingAdded: Bool { duplicates.isEmpty && overCap.isEmpty }
}
