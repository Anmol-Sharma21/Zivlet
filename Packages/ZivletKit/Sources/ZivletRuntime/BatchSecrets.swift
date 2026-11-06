import Foundation
import Synchronization
import ZivletCore

/// The passwords of one batch's jobs (plan 20f E3, D-M7-14), held for each job's whole life (its one crash retry
/// included) and wiped when it ends. One `JobSecrets` may serve several jobs ("the same password for all n files");
/// a secret is wiped when the last job that holds it ends, so no job loses its password to another's end.
public final class BatchSecrets: Sendable {
    private let held: Mutex<[JobID: JobSecrets]>

    public init(_ secrets: [JobID: JobSecrets]) {
        held = Mutex(secrets)
    }

    /// One set of secrets for every job of the batch.
    public static func shared(_ secrets: JobSecrets, for jobs: [JobID]) -> BatchSecrets {
        BatchSecrets(Dictionary(jobs.map { ($0, secrets) }, uniquingKeysWith: { first, _ in first }))
    }

    /// The job's secrets while it runs; nil once it ended (or for a job that has none).
    public func secrets(for job: JobID) -> JobSecrets? {
        held.withLock { $0[job] }
    }

    /// The job ended: its secrets are wiped unless another job still holds the same object.
    public func release(_ job: JobID) {
        let unused = held.withLock { held -> [JobSecret] in
            guard let ended = held.removeValue(forKey: job) else { return [] }
            let stillHeld = held.values.flatMap(\.all)
            return ended.all.filter { secret in !stillHeld.contains { $0 === secret } }
        }
        unused.forEach { $0.wipe() }
    }

    /// Every job ended (or none was submitted): everything is wiped.
    public func releaseAll() {
        let all = held.withLock { held in
            defer { held = [:] }
            return held.values.flatMap(\.all)
        }
        all.forEach { $0.wipe() }
    }
}
