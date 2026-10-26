/// Where a box item is now (D-M5b-3, P2-55 §9.5): present, in the Trash (which counts as missing), on a volume
/// that is not connected, or missing.
public enum ItemStatus: Sendable, Equatable {
    case present(path: String)
    case inTrash(path: String)
    case volumeOffline(name: String)
    case missing

    /// The Cocoa "no such file" code that both a deleted file and an unmounted volume give.
    static let fileNoSuchFile = 4
    static let trashFolders: Set<Substring> = [".Trash", ".Trashes"]

    /// Only a present item can be dragged out, shared or moved.
    public var isAvailable: Bool {
        if case .present = self { return true }
        return false
    }

    /// The rule of D-M5b-3. `isMounted` answers whether a volume path is mounted now.
    public static func from(_ resolution: Resolution, isMounted: (String) -> Bool) -> ItemStatus {
        switch resolution {
        case .resolved(let path, _):
            let inTrash = path.split(separator: "/").contains { trashFolders.contains($0) }
            return inTrash ? .inTrash(path: path) : .present(path: path)
        case .failed(let code, let volumePath?, let volumeName) where code == fileNoSuchFile && !isMounted(volumePath):
            let fallback = volumePath.split(separator: "/").last.map(String.init) ?? volumePath
            return .volumeOffline(name: volumeName ?? fallback)
        case .failed:
            return .missing
        }
    }
}
