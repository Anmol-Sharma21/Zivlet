import CoreGraphics
import Foundation
import ZivletCore

/// What one run of a locked file's job with a password gave: its result, the file still locked (the password did not
/// open it), or an error that is not about the password (a cancel, a dead worker, a damaged file).
public enum LockedAttempt<Value, Failure: Error> {
    case opened(Value)
    case stillLocked
    case failed(Failure)
}

/// How asking for one locked file ended.
public enum LockedOutcome<Value, Failure: Error> {
    case opened(Value)
    /// The person cancelled the sheet: the file stays locked.
    case skipped
    /// No sheet could open, because another tool's window is open.
    case unavailable
    /// The job was cancelled while it asked.
    case cancelled
    case failed(Failure)

    /// Nothing more is asked after this one: the job was cancelled, or no sheet can open.
    var endsTheAsking: Bool {
        switch self {
        case .cancelled, .unavailable: true
        case .opened, .skipped, .failed: false
        }
    }
}

extension LockedOutcome: Equatable where Value: Equatable, Failure: Equatable {}

/// A locked PDF in Copy Text or Read QR (P2-107, plan 20f E10, D-M7-24): one Open sheet per locked file, near the
/// working line, which asks for the file's password only (no Change: these tools never change the file, D-M7-61); each
/// password runs that file's own job, which carries it to the worker and wipes it when it ends. A password that does
/// not open the file (the job still says locked) brings the second sheet, which shakes, with no attempt limit; Cancel
/// skips the file. Any other error ends the asking for that file and is reported as itself, never as a wrong password;
/// a job cancelled meanwhile asks nothing more.
@MainActor
public enum LockedInputPrompting {
    public static func unlock<Value, Failure: Error>(
        _ file: URL, prompter: any PasswordPrompting, near point: CGPoint?,
        attempt: (JobSecrets) async -> LockedAttempt<Value, Failure>
    ) async -> LockedOutcome<Value, Failure> {
        let name = file.lastPathComponent
        let request = PasswordRequest(mode: .open, files: [name], near: point)
        var answer = await prompter.ask(request)
        while case .secrets(let secrets, _, _) = answer {
            switch await attempt(secrets) {
            case .opened(let value): return .opened(value)
            case .failed(let error): return .failed(error)
            case .stillLocked: if Task.isCancelled { return .cancelled }
            }
            answer = await prompter.retry(request, failed: [name])
        }
        return answer == .unavailable ? .unavailable : .skipped
    }

    /// Each locked file in turn, in drop order; the outcomes line up with `files`. Once one ends the asking, the files
    /// after it are skipped without a sheet.
    public static func unlockEach<Value, Failure: Error>(
        _ files: [URL], prompter: any PasswordPrompting, near point: CGPoint?,
        attempt: (URL, JobSecrets) async -> LockedAttempt<Value, Failure>
    ) async -> [LockedOutcome<Value, Failure>] {
        var outcomes: [LockedOutcome<Value, Failure>] = []
        for file in files {
            guard !(outcomes.last?.endsTheAsking ?? false), !Task.isCancelled else {
                outcomes.append(Task.isCancelled ? .cancelled : .skipped)
                continue
            }
            outcomes.append(await unlock(file, prompter: prompter, near: point) { await attempt(file, $0) })
        }
        return outcomes
    }
}
