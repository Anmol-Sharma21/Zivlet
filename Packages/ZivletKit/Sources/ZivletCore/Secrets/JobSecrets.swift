import Foundation

/// The passwords one job needs (plan 20c B1): the one that opens the input, the new user password (Lock, Change) and
/// the owner password (restrictions). Each is optional; the batch that holds them wipes them all when it ends.
public struct JobSecrets: Sendable, Equatable {
    public let input: JobSecret?
    public let newUser: JobSecret?
    public let owner: JobSecret?

    public init(input: JobSecret? = nil, newUser: JobSecret? = nil, owner: JobSecret? = nil) {
        self.input = input
        self.newUser = newUser
        self.owner = owner
    }

    /// Every secret held, without duplicates (the same object may fill two roles).
    public var all: [JobSecret] {
        [input, newUser, owner].compactMap { $0 }.reduce(into: []) { found, secret in
            if !found.contains(where: { $0 === secret }) { found.append(secret) }
        }
    }

    /// Zeroes every secret held.
    public func wipeAll() {
        all.forEach { $0.wipe() }
    }
}
