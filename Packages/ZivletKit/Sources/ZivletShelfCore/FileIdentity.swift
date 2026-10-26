/// Which file an item is, independent of its name and folder (P2-141 de-dup): the volume's UUID and the file's
/// identifier on that volume. Read through `BookmarkMaking.identity(of:)`; nil where the volume has none.
public struct FileIdentity: Sendable, Hashable, Codable {
    /// Longest volume UUID string accepted from disk; a UUID string is 36 characters.
    static let maxVolumeLength = 128

    public let volumeUUID: String
    public let fileID: UInt64

    public init(volumeUUID: String, fileID: UInt64) {
        self.volumeUUID = volumeUUID
        self.fileID = fileID
    }

    var isValid: Bool { !volumeUUID.isEmpty && volumeUUID.utf8.count <= Self.maxVolumeLength }
}
