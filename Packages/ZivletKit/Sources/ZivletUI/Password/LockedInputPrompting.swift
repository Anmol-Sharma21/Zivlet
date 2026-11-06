import CoreGraphics
import Foundation
import ZivletCore

/// A locked PDF in Copy Text or Read QR (P2-107, plan 20f E10, D-M7-24): one Unlock sheet per locked file, near the
/// working line; each password runs that file's own job, which carries it to the worker and wipes it when it ends. A
/// password that does not open the file (the job still says locked) brings the second sheet, which shakes, with no
/// attempt limit; Cancel skips the file.
@MainActor
public enum LockedInputPrompting {
    /// `attempt` runs the file's job with the secrets and gives its result, or nil when the file stayed locked.
    public static func unlock<Value>(
        _ file: URL, prompter: any PasswordPrompting, near point: CGPoint?,
        attempt: (JobSecrets) async -> Value?
    ) async -> Value? {
        let name = file.lastPathComponent
        let request = PasswordRequest(mode: .unlock, files: [name], near: point)
        var answer = await prompter.ask(request)
        while case .secrets(let secrets, _, _) = answer {
            if let value = await attempt(secrets) { return value }
            answer = await prompter.retry(request, failed: [name])
        }
        return nil
    }

    /// Each locked file in turn, in drop order; only the files that opened are in the result.
    public static func unlockEach<Value>(
        _ files: [URL], prompter: any PasswordPrompting, near point: CGPoint?,
        attempt: (URL, JobSecrets) async -> Value?
    ) async -> [URL: Value] {
        var opened: [URL: Value] = [:]
        for file in files {
            if let value = await unlock(file, prompter: prompter, near: point, attempt: { await attempt(file, $0) }) {
                opened[file] = value
            }
        }
        return opened
    }
}
