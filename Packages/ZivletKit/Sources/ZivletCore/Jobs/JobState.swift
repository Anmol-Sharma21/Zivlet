import Foundation

/// Progress of one job (02 §7.2, trimmed for M3). `fraction == nil` means indeterminate. Invariant: a fraction is
/// finite and in 0...1 (out-of-range values are clamped, non-finite ones become indeterminate).
public struct JobProgress: Sendable, Equatable, Codable {
    public let fraction: Double?

    public init(fraction: Double?) {
        guard let fraction, fraction.isFinite else {
            self.fraction = nil
            return
        }
        self.fraction = min(1, max(0, fraction))
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
