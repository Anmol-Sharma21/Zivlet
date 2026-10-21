import Foundation
import ZivletCore

/// Free space on the volume of a folder; nil when the system cannot say.
public protocol FreeSpaceReading: Sendable {
    func freeBytes(at folder: URL) -> Int64?
}

/// `volumeAvailableCapacityForImportantUsage`: what a user-initiated write can count on, purgeable space included.
/// FAT32 and exFAT volumes (camera cards, USB sticks) report 0 for it whatever is free, so a 0 falls back to
/// `volumeAvailableCapacity`.
public struct VolumeFreeSpace: FreeSpaceReading {
    public init() {}

    public func freeBytes(at folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        return Self.resolve(
            important: values?.volumeAvailableCapacityForImportantUsage,
            available: values?.volumeAvailableCapacity.map(Int64.init))
    }

    static func resolve(important: Int64?, available: Int64?) -> Int64? {
        if let important, important > 0 { return important }
        return available
    }
}

/// Refuses a job up front when its output could fill the disk (P1-13, 03a §4.2, 10 §8.6): free space must be at least
/// 1.5 × the estimated output plus 512 MB. Pure.
public enum DiskPreflight {
    public static let reserveBytes: Int64 = 512 * 1_024 * 1_024
    public static let headroom = 1.5

    /// What the engine may write before the reserve is touched; nil (no cap) when free space is unknown.
    public static func outputLimit(freeBytes: Int64?) -> Int64? {
        freeBytes.map { max(0, $0 - reserveBytes) }
    }

    /// An unknown free space (network volumes, odd file systems) does not block the job; the write itself still
    /// reports `diskFull` if the volume fills up.
    public static func check(estimatedBytes: Int64, freeBytes: Int64?) throws(JobError) {
        guard let freeBytes else { return }
        let needed = Double(max(0, estimatedBytes)) * headroom + Double(reserveBytes)
        guard Double(freeBytes) >= needed else { throw .diskFull }
    }
}
