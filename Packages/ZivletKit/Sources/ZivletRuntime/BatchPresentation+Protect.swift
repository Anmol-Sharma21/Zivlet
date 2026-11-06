import Foundation
import ZivletCore

/// LOCK · UNLOCK's words (plan 20f E8): the card says what happened rather than "Saved", lists files a mixed drop left
/// as they were (not failures), and counts files whose password did not open them.
extension ProtectSpec.Mode {
    /// The card's line once the job is done.
    public var doneLine: String {
        switch self {
        case .lock: "Locked with AES-256"
        case .unlock: "Unlocked"
        case .changePassword: "Password changed"
        }
    }

    /// The working title.
    public var workingTitle: String {
        switch self {
        case .lock: "Locking"
        case .unlock: "Unlocking"
        case .changePassword: "Changing password"
        }
    }
}

extension BatchPresentation {
    /// The title while a batch runs: the protect mode, or "Converting to JPG".
    public static func workingTitle(_ snapshot: BatchSnapshot, registry: FormatRegistry = .standard) -> String {
        snapshot.protect?.workingTitle ?? "Converting to \(registry.format(snapshot.target).wheelLabel)"
    }

    /// A finished protect batch. Inputs already locked in a Lock drop are notes, not failures (D-M7-19).
    static func protect(_ snapshot: BatchSnapshot, mode: ProtectSpec.Mode, notes: [String]) -> BatchPresentation {
        let saved = snapshot.outputs
        let leftAlone = snapshot.items.filter { $0.state == .failed(.alreadyEncrypted) }
        let failed = snapshot.items.filter { $0.state.isFailure && $0.state != .failed(.alreadyEncrypted) }
        let allNotes = notes + leftAlone.map { "\($0.name): \(JobErrorCopy.copy(for: .alreadyEncrypted).message)" }
        if failed.isEmpty, !saved.isEmpty {
            let subtitle = saved.count == 1 ? saved[0].url.lastPathComponent : "\(saved.count) files"
            return BatchPresentation(
                phase: .succeeded, title: mode.doneLine, subtitle: subtitle, fraction: nil, notes: allNotes,
                detail: nil)
        }
        guard !saved.isEmpty else { return failedProtect(snapshot, failed: failed, notes: allNotes) }
        let total = saved.count + failed.count
        return BatchPresentation(
            phase: .partial, title: "\(mode.doneLine) \(saved.count) of \(total) files",
            subtitle: partialLine(failed), fraction: nil, notes: allNotes, detail: nil)
    }

    /// "1 file not unlocked" when every failure is a password that did not open its file; else the first reason.
    private static func partialLine(_ failed: [BatchItem]) -> String {
        let passwords: [JobState] = [.failed(.wrongPassword), .failed(.ownerPasswordNeeded)]
        if failed.allSatisfy({ passwords.contains($0.state) }) { return notUnlockedLine(failed.count) }
        guard let first = failed.first, case .failed(let error) = first.state else { return "" }
        return "\(first.name): \(JobErrorCopy.copy(for: error).message)"
    }

    private static func failedProtect(
        _ snapshot: BatchSnapshot, failed: [BatchItem], notes: [String]
    ) -> BatchPresentation {
        let shown = failed.isEmpty ? snapshot.items.filter(\.state.isFailure) : failed
        guard let first = shown.first, case .failed(let error) = first.state else {
            return BatchPresentation(
                phase: .cancelled, title: "Cancelled", subtitle: "Nothing was saved.", fraction: nil, notes: [],
                detail: nil)
        }
        let copy = JobErrorCopy.copy(for: error)
        let single = snapshot.items.count == 1
        return BatchPresentation(
            phase: .failed, title: single ? copy.message : "None of the \(snapshot.items.count) files were changed",
            subtitle: single ? first.name : "\(first.name): \(copy.message)", fraction: nil,
            notes: failed.isEmpty ? [] : notes, detail: copy.detail)
    }

    /// The card's line for files that stayed locked (17b §3.3).
    public static func notUnlockedLine(_ count: Int) -> String {
        count == 1 ? "1 file not unlocked" : "\(count) files not unlocked"
    }
}

extension JobState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
