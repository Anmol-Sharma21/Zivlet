import Foundation
import ZivletCore

/// The worker protocol's version (02 §7.5). Bump it whenever a message changes shape; app and worker ship together,
/// so a mismatch means a damaged or mixed install.
public enum WorkerProtocol {
    /// 2: the text requests and replies of Copy Text (plan 18d D8).
    public static let version = 3
}

public enum WorkerProtocolError: Error, Equatable, Sendable {
    case versionMismatch(expected: Int, found: Int)

    /// What a job reports: the worker does not belong to this app (02 §7.5).
    public var jobError: JobError { .engineDamaged(.worker) }
}

/// Every message on the wire: the protocol version and one body. Decoding refuses another version before the body
/// is read, so a body of another shape never reaches the code.
public struct Envelope<Body: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let body: Body

    public init(_ body: Body) {
        self.init(protocolVersion: WorkerProtocol.version, body: body)
    }

    public init(protocolVersion: Int, body: Body) {
        self.protocolVersion = protocolVersion
        self.body = body
    }

    private enum CodingKeys: String, CodingKey { case protocolVersion, body }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let found = try c.decode(Int.self, forKey: .protocolVersion)
        guard found == WorkerProtocol.version else {
            throw WorkerProtocolError.versionMismatch(expected: WorkerProtocol.version, found: found)
        }
        self.init(protocolVersion: found, body: try c.decode(Body.self, forKey: .body))
    }

    /// Decodes JSON (the loopback transport and the tests); XPC decodes with its own decoder through `init(from:)`.
    public static func decode(_ data: Data) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: data)
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
