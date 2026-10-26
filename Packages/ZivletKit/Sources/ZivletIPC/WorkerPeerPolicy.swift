import Foundation
import Security
import ZivletEngineKit
import os

/// Who signed the running code: its Team ID (nil when ad-hoc) and signing identifier.
public struct SigningIdentity: Sendable, Equatable {
    public let teamID: String?
    public let identifier: String?

    public init(teamID: String?, identifier: String?) {
        self.teamID = teamID
        self.identifier = identifier
    }

    /// Read from the running process's own signature (`SecCodeCopySelf`), never from a build flag (D-M6-7).
    public static func current() -> SigningIdentity {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess, let values = info as? [String: Any]
        else { return SigningIdentity(teamID: nil, identifier: nil) }
        return SigningIdentity(
            teamID: values[kSecCodeInfoTeamIdentifier as String] as? String,
            identifier: values[kSecCodeInfoIdentifier as String] as? String)
    }
}

/// What a peer must satisfy; the two XPC files map it to `XPCPeerRequirement`.
public enum PeerRequirementSpec: Sendable, Equatable {
    /// Signed by this code's team, with this signing identifier (Developer ID builds).
    case sameTeam(identifier: String)
    /// Only the signing identifier (ad-hoc builds, which have no team; weaker, R3).
    case signingIdentifier(String)
}

/// The peer rule of both sides (03b "XPC peer spoofing", D-M6-7): the app requires the worker's identifier, the
/// worker the app's; with a valid Team ID the peer must also share it. A malformed Team ID takes the ad-hoc path
/// with a warning, so it is never interpolated into a requirement.
public enum WorkerPeerPolicy {
    public static let appIdentifier = "app.zivlet.Zivlet"
    public static let workerIdentifier = "app.zivlet.Zivlet.Worker"
    /// The XPC service name is the worker bundle's identifier.
    public static let workerServiceName = workerIdentifier
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "scheduler")

    public static func requirement(own: SigningIdentity, peer: String) -> PeerRequirementSpec {
        guard let team = own.teamID else { return .signingIdentifier(peer) }
        guard HelperIntegrity.Policy.validTeamID(team) else {
            logger.error("Malformed Team ID in the running code; the worker peer check uses the identifier only")
            return .signingIdentifier(peer)
        }
        return .sameTeam(identifier: peer)
    }
}
