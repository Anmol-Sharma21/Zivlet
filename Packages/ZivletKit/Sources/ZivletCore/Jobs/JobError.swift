/// Why an input was refused (02 §9 "Input" row). Raw values are stable for JSON.
public enum InputRejection: String, Sendable, Codable, Equatable {
    /// Not a local regular file with a safe absolute path.
    case notAFile
    /// The file could not be opened or read.
    case unreadable
    /// The extension names no known format.
    case unknownFormat
    /// The contents are not what the extension says (for example a playlist named `.mp4`).
    case contentMismatch
    case noAudioTrack
    case noVideoTrack
    /// Above a safety limit (pixel count, probe size).
    case tooLarge
    /// A PDF above the input size limit (D-M7-18).
    case pdfTooLarge
    /// A PDF past a parser or page limit: nesting, filters, containers (D-M7-18).
    case pdfTooComplex
    /// A PDF qpdf cannot read, or one with too many warnings to write from (D-M7-18).
    case pdfDamaged
    /// A password outside 1…127 UTF-8 bytes, or more passwords than a job takes (plan 20f E3).
    case badPassword
}

/// The one error taxonomy (02 §9, 10 §8.4). Carries no user copy; `JobErrorCopy` maps cases to sentences.
/// Every engine and runtime failure is converted to a case here, so nothing is swallowed or stringly typed.
public enum JobError: Error, Sendable, Equatable, Codable {
    // input
    case pairNotSupported(FormatID, FormatID)
    case unsupportedInput(InputRejection)
    /// LOCK · UNLOCK's Lock got a PDF that already has encryption (plan 20f E4): it is left as it is.
    case alreadyEncrypted
    // environment
    /// The route exists but this machine's engine lacks what it needs (an encoder, a filter, a renderer).
    case routeUnavailable(FormatID, FormatID, [String])
    case engineMissing(EngineID)
    /// A bundled helper failed its code-signature check (P1-50): modified, unsigned or outside the app.
    case engineDamaged(EngineID)
    case invalidDestination
    case permissionDenied(folder: String)
    case diskFull
    // execution
    case processFailed(status: Int32, stderrTail: String)
    case crashed(signal: Int32)
    /// A helper that exists could not be started or waited on (EMFILE, EAGAIN, ECHILD): not a missing engine.
    case helperFailed(errno: Int32)
    /// The helper made no progress for its watchdog limit and was stopped (03a §4.6).
    case stalled
    case cancelled
    /// The worker process ended while this job's step was in flight (P2-01); the job is retried once.
    case workerCrashed
    /// The worker ended twice while running this file: the file is the likely cause, so it is not tried again.
    case engineCrashedOnInput
    // outcome
    case verificationFailed(String)
    /// The engine could not write its output (an encoder or Quartz failure that is not the input's fault).
    case writeFailed(String)
    case publishFailed(errno: Int32)
    /// A bug: an invariant Zivlet relies on did not hold.
    case internalInvariant(String)
}
