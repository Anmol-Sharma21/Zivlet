import Foundation
import ZivletCore

/// Runs LOCK · UNLOCK's jobs for the sheet's batch logic (plan 20f E7): one job per file with that file's secrets, and
/// each file's final state when the batch ends. `ConversionService` is the real one; the secrets are wiped as each
/// job ends (D-M7-14).
public protocol ProtectSubmitting: Sendable {
    func protect(_ files: [URL], spec: ProtectSpec, secrets: [URL: JobSecrets]) async -> [URL: JobState]
}
