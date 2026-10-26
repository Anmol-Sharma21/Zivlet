import Foundation

/// Reads every `*.json` trace directly in a folder (OS-M5b-1). A file that cannot be read or fails validation is
/// listed with its name and reason and left out; nothing is skipped silently. Files are read in name order and each
/// is capped in size before it is decoded.
public enum DragTraceFolder {
    /// 20,000 samples of about 60 bytes each, with room to spare.
    public static let maxFileBytes = 4 * 1_024 * 1_024

    public struct Loaded: Sendable, Equatable {
        public let traces: [Named]
        public let invalid: [Refused]
    }

    public struct Named: Sendable, Equatable {
        public let name: String
        public let trace: DragTrace
    }

    public struct Refused: Sendable, Equatable {
        public let name: String
        public let reason: String
    }

    public static func load(from folder: URL) throws -> Loaded {
        let files = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var traces: [Named] = []
        var invalid: [Refused] = []
        for file in files {
            switch read(file) {
            case .success(let trace): traces.append(Named(name: file.lastPathComponent, trace: trace))
            case .failure(let reason): invalid.append(Refused(name: file.lastPathComponent, reason: reason.text))
            }
        }
        return Loaded(traces: traces, invalid: invalid)
    }

    private static func read(_ file: URL) -> Result<DragTrace, Reason> {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true else { return .failure(Reason(text: "not a regular file")) }
        guard (values?.fileSize ?? 0) <= maxFileBytes else {
            return .failure(Reason(text: "larger than \(maxFileBytes / 1_048_576) MB"))
        }
        do {
            return .success(try JSONDecoder().decode(DragTrace.self, from: Data(contentsOf: file)))
        } catch let error as DragTraceError {
            return .failure(Reason(text: error.description))
        } catch is DecodingError {
            return .failure(Reason(text: "not a drag trace (a field is missing or has the wrong type)"))
        } catch {
            return .failure(Reason(text: "could not be read"))
        }
    }

    private struct Reason: Error {
        let text: String
    }
}
