extension JobError {
    /// A line that is safe to log with `privacy: .public` (01 NFR-6: paths stay private): the case name with its
    /// numbers, formats and missing capability names. Folders, stderr tails and free-text details are left out,
    /// because they can hold paths; log `String(describing:)` with `privacy: .private` when they are needed.
    public var logDescription: String {
        switch self {
        case .pairNotSupported(let source, let target): "pairNotSupported(\(source.rawValue) → \(target.rawValue))"
        case .unsupportedInput(let reason): "unsupportedInput(\(reason.rawValue))"
        case .routeUnavailable(let source, let target, let missing):
            "routeUnavailable(\(source.rawValue) → \(target.rawValue), missing: \(missing.joined(separator: ", ")))"
        case .engineMissing(let engine): "engineMissing(\(engine.rawValue))"
        case .engineDamaged(let engine): "engineDamaged(\(engine.rawValue))"
        case .invalidDestination: "invalidDestination"
        case .permissionDenied: "permissionDenied"
        case .diskFull: "diskFull"
        case .processFailed(let status, _): "processFailed(status: \(status))"
        case .crashed(let signal): "crashed(signal: \(signal))"
        case .helperFailed(let code): "helperFailed(errno: \(code))"
        case .stalled: "stalled"
        case .cancelled: "cancelled"
        case .verificationFailed: "verificationFailed"
        case .writeFailed: "writeFailed"
        case .publishFailed(let code): "publishFailed(errno: \(code))"
        case .internalInvariant: "internalInvariant"
        }
    }
}
