import Foundation

/// One local input file (02 §7.2). Invariant: a file URL with a safe absolute path that names a file, and a
/// non-negative size. `quarantine` is the source's `com.apple.quarantine` value, copied onto outputs (10 §8.5).
public struct InputItem: Sendable, Hashable, Codable {
    public let url: URL
    public let format: FormatID
    public let byteCount: Int64
    public let quarantine: Data?

    public init(url: URL, format: FormatID, byteCount: Int64, quarantine: Data? = nil) throws(JobError) {
        guard url.isFileURL, PathRules.isSafeAbsolute(url.path), !url.lastPathComponent.isEmpty,
            url.path != "/", byteCount >= 0
        else { throw .unsupportedInput(.notAFile) }
        self.url = url
        self.format = format
        self.byteCount = byteCount
        self.quarantine = quarantine
    }

    public var fileName: String { url.lastPathComponent }
}

/// What a job does. M3 has conversions only; tools add cases later.
public enum JobOperation: Sendable, Hashable, Codable {
    case convert(FormatID)
}

/// An immutable conversion request (02 §7.2, adapted for M3: one input per job, a resolved destination folder).
/// Invariant: the pair is in the catalog and the destination is a safe absolute folder path.
public struct JobRequest: Sendable, Hashable, Codable {
    public let id: JobID
    public let input: InputItem
    public let operation: JobOperation
    public let destination: URL

    public init(
        id: JobID = JobID(), input: InputItem, operation: JobOperation, destination: URL,
        catalog: ConversionCatalog = .standard
    ) throws(JobError) {
        guard destination.isFileURL, PathRules.isSafeAbsolute(destination.path) else { throw .invalidDestination }
        let request = Self(unchecked: id, input, operation, destination)
        guard catalog.canConvert(input.format, to: request.target) else {
            throw .pairNotSupported(input.format, request.target)
        }
        self = request
    }

    private init(unchecked id: JobID, _ input: InputItem, _ operation: JobOperation, _ destination: URL) {
        self.id = id
        self.input = input
        self.operation = operation
        self.destination = destination
    }

    public var target: FormatID {
        switch operation {
        case .convert(let format): format
        }
    }

    public var pair: ConversionPair { ConversionPair(source: input.format, target: target) }
}

extension InputItem {
    private enum CodingKeys: String, CodingKey { case url, format, byteCount, quarantine }

    /// Decoding is a boundary (worker IPC in P2): it runs the same checks as `init`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            url: c.decode(URL.self, forKey: .url), format: c.decode(FormatID.self, forKey: .format),
            byteCount: c.decode(Int64.self, forKey: .byteCount),
            quarantine: c.decodeIfPresent(Data.self, forKey: .quarantine))
    }
}

extension JobRequest {
    private enum CodingKeys: String, CodingKey { case id, input, operation, destination }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: c.decode(JobID.self, forKey: .id), input: c.decode(InputItem.self, forKey: .input),
                operation: c.decode(JobOperation.self, forKey: .operation),
                destination: c.decode(URL.self, forKey: .destination))
        } catch let error as JobError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid job request", underlyingError: error))
        }
    }
}

/// Path checks shared by inputs and destinations: absolute, no Unicode Cc characters, no ".." component.
enum PathRules {
    static func isSafeAbsolute(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.unicodeScalars.contains { $0.properties.generalCategory == .control }
            && !path.split(separator: "/").contains("..")
    }
}
