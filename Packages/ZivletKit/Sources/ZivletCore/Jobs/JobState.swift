import Foundation

/// Progress of one job (02 §7.2, 03a §4.5). `fraction == nil` means indeterminate (unknown duration); then
/// `bytesWritten` is what the HUD shows. Invariants: a fraction is finite and in 0...1 (clamped; non-finite becomes
/// indeterminate), `0 <= stage < stageCount`, and bytes and ETA are never negative (dropped otherwise).
public struct JobProgress: Sendable, Equatable, Codable {
    public let fraction: Double?
    public let stage: Int
    public let stageCount: Int
    public let bytesWritten: Int64?
    public let eta: Duration?

    public init(
        fraction: Double?, stage: Int = 0, stageCount: Int = 1, bytesWritten: Int64? = nil, eta: Duration? = nil
    ) {
        if let fraction, fraction.isFinite {
            self.fraction = min(1, max(0, fraction))
        } else {
            self.fraction = nil
        }
        self.stageCount = max(1, stageCount)
        self.stage = (0..<self.stageCount).contains(stage) ? stage : 0
        self.bytesWritten = bytesWritten.flatMap { $0 >= 0 ? $0 : nil }
        self.eta = eta.flatMap { $0 >= .zero ? $0 : nil }
    }
}

/// A published output file. `fileID` (inode), `byteCount` and `modified` are read at publish time, so Undo trashes
/// only the file Zivlet wrote (03a §4.7).
public struct PublishedOutput: Sendable, Equatable, Codable {
    public let url: URL
    public let format: FormatID
    public let byteCount: Int64
    public let fileID: UInt64
    public let modified: Date

    public init(url: URL, format: FormatID, byteCount: Int64, fileID: UInt64, modified: Date) {
        self.url = url
        self.format = format
        self.byteCount = byteCount
        self.fileID = fileID
        self.modified = modified
    }
}

/// Lifecycle of one job (03a §4.1): queued → preparing (probe + plan) → running → verifying → publishing → outcome.
public enum JobState: Sendable, Equatable, Codable {
    case queued, preparing
    case running(JobProgress)
    case verifying, publishing
    case succeeded(PublishedOutput)
    case failed(JobError)
    case cancelled

    /// The output of a succeeded job.
    public var published: PublishedOutput? {
        guard case .succeeded(let output) = self else { return nil }
        return output
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: true
        default: false
        }
    }
}
