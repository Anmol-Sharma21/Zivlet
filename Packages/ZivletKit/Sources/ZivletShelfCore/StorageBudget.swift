/// The owned-copy warning (OWN-APP-3): from 2 GB, counted in decimal bytes as Finder shows them.
public enum StorageBudget {
    public static let warnBytes: Int64 = 2_000_000_000

    public static func isOverWarning(_ bytes: Int64) -> Bool { bytes >= warnBytes }
}
