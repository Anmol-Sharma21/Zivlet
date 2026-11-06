import AppKit
import ZivletCore
import ZivletRuntime
import ZivletUI

/// LOCK · UNLOCK in the app (plan 20f E9, D-M7-19): a drop asks the worker what each PDF is (no password), opens the
/// right sheet at the wheel's place, and runs one job per file through the conversion service, so its card shows
/// near the drop or at the notch like any batch. A failed card's Retry reopens the sheet for its failed files.
@MainActor
final class ProtectWiring {
    private let conversions: ConversionService
    private let prompter: any PasswordPrompting
    private let expectBatch: @MainActor @Sendable (CGPoint?) -> Void

    /// `expectBatch` tells the result presenters that a batch is coming from `point`, once per batch.
    init(
        conversions: ConversionService, prompter: any PasswordPrompting,
        expectBatch: @escaping @MainActor @Sendable (CGPoint?) -> Void
    ) {
        self.conversions = conversions
        self.prompter = prompter
        self.expectBatch = expectBatch
    }

    func run(_ urls: [URL], near point: CGPoint?) {
        let flow = flow(near: point)
        Task { await flow.run(urls, near: point) }
    }

    func retry(_ retry: ProtectRetry, near point: CGPoint?) {
        let flow = flow(near: point)
        Task { await flow.retry(retry, near: point) }
    }

    /// The flow with this prompter, or another one (the DEBUG demo answers for itself).
    func flow(near point: CGPoint?, prompter: (any PasswordPrompting)? = nil) -> ProtectFlow {
        let conversions = self.conversions
        let expectBatch = self.expectBatch
        let submitter = AnnouncedSubmitter(conversions: conversions) { await expectBatch(point) }
        return ProtectFlow(
            inspect: { files in await conversions.inspectPDFs(files) }, prompter: prompter ?? self.prompter,
            submitter: submitter)
    }
}

/// Each batch is announced to the presenters before it is submitted, so its card opens where the drop was.
private struct AnnouncedSubmitter: ProtectSubmitting {
    let conversions: ConversionService
    let announce: @Sendable () async -> Void

    func protect(_ files: [URL], spec: ProtectSpec, secrets: [URL: JobSecrets]) async -> [URL: JobState] {
        await announce()
        return await conversions.protect(files, spec: spec, secrets: secrets)
    }
}
