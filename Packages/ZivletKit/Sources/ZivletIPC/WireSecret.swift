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
