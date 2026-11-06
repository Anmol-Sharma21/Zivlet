import Foundation
import ZivletCore

/// A `JobSecret` on the worker's wire (plan 20c B1, D-M7-14): its bytes as `Data` inside the one request of its job,
/// and a new `JobSecret` on the other side. Only requests of a job that needs a password carry one; nothing else in the
/// app can encode a secret. Descriptions and the mirror show `<password>`, never the bytes or their count.
///
/// The `Data` and the encoder's and XPC's own buffers are freed without being zeroed (best effort, G-M7-5): the
/// request lives only for the time it takes to send or to rebuild the secret.
struct WireSecret: Codable, Sendable, Equatable {
    private let bytes: Data

    init(_ secret: JobSecret) {
        bytes = secret.withBytes { Data($0) }
    }

    /// The secret again, in its own buffer, for the job that receives it.
    func secret() -> JobSecret {
        JobSecret(bytes: bytes)
    }

    init(from decoder: any Decoder) throws {
        bytes = try decoder.singleValueContainer().decode(Data.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }
}

extension WireSecret: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { JobSecret.redacted }
    var debugDescription: String { JobSecret.redacted }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

extension WireSecret {
    /// How many bytes the password has; the validator reads this, never the bytes.
    var byteCount: Int { bytes.count }
}

/// A job's passwords on the worker's wire (plan 20f E3, D-M7-14): made from its `JobSecrets` right before a request of
/// that job is sent, and turned back into `JobSecrets` in the worker for that one step. Each entry names its role; the
/// validator refuses more than three, a role twice and any password outside 1…127 bytes (R6's limit).
public struct WireSecrets: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        case input, newUser, owner
    }

    public struct Entry: Codable, Sendable, Equatable {
        public let role: Role
        let secret: WireSecret

        public init(_ role: Role, _ secret: JobSecret) {
            self.role = role
            self.secret = WireSecret(secret)
        }
    }

    let entries: [Entry]

    /// Nil when there is nothing to send.
    public init?(entries: [Entry]) {
        guard !entries.isEmpty else { return nil }
        self.entries = entries
    }

    /// The wire form of `secrets`; nil for no secrets at all.
    public init?(_ secrets: JobSecrets?) {
        guard let secrets else { return nil }
        let roles: [(Role, JobSecret?)] = [
            (.input, secrets.input), (.newUser, secrets.newUser), (.owner, secrets.owner),
        ]
        self.init(entries: roles.compactMap { role, secret in secret.map { Entry(role, $0) } })
    }

    public var count: Int { entries.count }

    /// The roles in order, for the validator.
    var roles: [Role] { entries.map(\.role) }

    /// Each password's length in bytes, for the validator.
    var byteCounts: [Int] { entries.map(\.secret.byteCount) }

    /// New secrets, each in its own buffer, for the one step that received them; the step wipes them when it ends.
    public func secrets() -> JobSecrets {
        let secret = { (role: Role) in entries.last { $0.role == role }?.secret.secret() }
        return JobSecrets(input: secret(.input), newUser: secret(.newUser), owner: secret(.owner))
    }
}
