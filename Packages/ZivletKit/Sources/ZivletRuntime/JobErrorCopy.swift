import Darwin
import Foundation
import ZivletCore

/// One sentence for the HUD and, optionally, the technical detail behind "Show details".
public struct ErrorCopy: Sendable, Equatable {
    public let message: String
    public let detail: String?

    public init(_ message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
}

/// User copy for every `JobError` case (02 §9, 10 §8.4). Zivlet's own wording. It lives in the runtime until the
/// ZivletUI module and its string catalog exist (index D-M3-12).
public enum JobErrorCopy {
    static let stderrLines = 12

    public static func copy(for error: JobError, registry: FormatRegistry = .standard) -> ErrorCopy {
        func label(_ format: FormatID) -> String { registry.format(format).wheelLabel }
        switch error {
        case .pairNotSupported(let source, let target):
            return ErrorCopy("Zivlet can't convert \(label(source)) files to \(label(target)).")
        case .unsupportedInput(let reason):
            return ErrorCopy(input(reason))
        case .routeUnavailable(_, let target, let missing):
            return ErrorCopy(
                "Converting to \(label(target)) isn't available on this Mac yet.",
                detail: "Missing: \(missing.joined(separator: ", ")).")
        default:
            return environment(error) ?? outcome(error)
        }
    }

    private static func input(_ reason: InputRejection) -> String {
        switch reason {
        case .notAFile: "This item isn't a file Zivlet can convert."
        case .unreadable: "This file couldn't be read. It may be damaged."
        case .unknownFormat: "Zivlet doesn't recognise this kind of file."
        case .contentMismatch: "This file's contents don't match its extension."
        case .noAudioTrack: "This file has no audio to convert."
        case .noVideoTrack: "This file has no video to convert."
        case .tooLarge: "This file is larger than Zivlet's safety limit."
        }
    }

    private static func environment(_ error: JobError) -> ErrorCopy? {
        switch error {
        case .engineMissing(.media): ErrorCopy("Zivlet's media engine wasn't found.", detail: mediaEngineHint)
        case .engineMissing(.image): ErrorCopy("Zivlet's image engine isn't available.")
        case .engineDamaged(.media): ErrorCopy("Zivlet's media engine is damaged. Reinstall Zivlet to fix it.")
        case .engineDamaged(.image): ErrorCopy("Zivlet's image engine is damaged. Reinstall Zivlet to fix it.")
        case .engineMissing(.worker): ErrorCopy("Zivlet's converter isn't available.")
        case .engineDamaged(.worker): ErrorCopy("Zivlet's converter is damaged. Reinstall Zivlet.")
        case .invalidDestination: ErrorCopy("The folder for the result isn't available any more.")
        case .permissionDenied(let folder):
            ErrorCopy(
                "macOS didn't allow saving in “\(URL(fileURLWithPath: folder).lastPathComponent)”.",
                detail: "Allow access in System Settings › Privacy & Security.")
        case .diskFull: ErrorCopy("There isn't enough free disk space.")
        default: nil
        }
    }

    /// Only Debug builds name the developer tool folders, so a Release binary holds no Homebrew path (P1-21).
    static var mediaEngineHint: String {
        #if DEBUG
            "Developer builds look in ZIVLET_FFMPEG_DIR, /opt/homebrew/bin and /usr/local/bin."
        #else
            "Reinstalling Zivlet restores it."
        #endif
    }

    private static func outcome(_ error: JobError) -> ErrorCopy {
        switch error {
        case .processFailed(let status, let tail):
            ErrorCopy("The conversion failed.", detail: "Exit status \(status).\n" + lastLines(tail))
        case .crashed(let signal): ErrorCopy("The converter stopped unexpectedly.", detail: "Signal \(signal).")
        case .helperFailed(let code): ErrorCopy("Zivlet couldn't start its converter.", detail: helperDetail(code))
        case .stalled:
            ErrorCopy("The converter stopped making progress, so Zivlet stopped it.", detail: "No progress for 60 s.")
        case .cancelled: ErrorCopy("Cancelled.")
        case .verificationFailed(let detail):
            ErrorCopy("The result didn't pass checks and wasn't saved.", detail: detail)
        case .writeFailed(let detail): ErrorCopy("The converted file couldn't be written.", detail: detail)
        case .publishFailed(let code):
            ErrorCopy("The result couldn't be saved.", detail: String(cString: strerror(code)))
        case .internalInvariant(let detail): ErrorCopy("Something went wrong inside Zivlet.", detail: detail)
        default: ErrorCopy("Something went wrong inside Zivlet.", detail: String(describing: error))
        }
    }

    /// Running out of descriptors or processes is something the user can act on; other errnos are shown as is.
    static func helperDetail(_ code: Int32) -> String {
        switch code {
        case EMFILE, ENFILE, EAGAIN: "Too many conversions are running. Try fewer files at once."
        default: String(cString: strerror(code)) + "."
        }
    }

    static func lastLines(_ text: String) -> String {
        text.split(separator: "\n").suffix(stderrLines).joined(separator: "\n")
    }
}
