import Foundation
import Security
import ZivletCore
import os

/// Checks a bundled helper's code signature before its first use in a launch (P1-50, 11 §7.4). The helper must live
/// inside the app bundle and carry a valid signature over every architecture; when the app itself has a Team ID,
/// the helper must be signed by the same team. Damage is reported as `JobError.engineDamaged`.
public enum HelperIntegrity {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "engine")
    static let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)

    /// What a helper must satisfy: a Team ID to match (nil for an ad-hoc signed app) and the bundle it must live in.
    public struct Policy: Sendable, Equatable {
        public let teamID: String?
        public let bundleRoot: URL

        public init(teamID: String?, bundleRoot: URL) {
            self.teamID = teamID
            self.bundleRoot = bundleRoot
        }

        /// The code requirement for the Team ID; nil without one, and nil for a malformed one (never interpolated).
        public var requirement: String? {
            guard let teamID, Self.validTeamID(teamID) else { return nil }
            return #"anchor apple generic and certificate leaf[subject.OU] = "\#(teamID)""#
        }

        /// Apple Team IDs are ten upper-case letters or digits.
        public static func validTeamID(_ text: String) -> Bool {
            text.utf8.count == 10 && text.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) }
        }

        /// The running app's policy: its own Team ID (none when ad-hoc signed) and its bundle.
        public static func current() -> Policy {
            Policy(teamID: runningTeamID(), bundleRoot: Bundle.main.bundleURL)
        }

        static func runningTeamID() -> String? {
            var code: SecCode?
            var staticCode: SecStaticCode?
            var info: CFDictionary?
            guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
                SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
                SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                    == errSecSuccess
            else { return nil }
            return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        }
    }

    /// Throws `engineDamaged(engine)` unless `tool` is inside the policy's bundle and validly signed for it.
    public static func check(_ tool: URL, policy: Policy, engine: EngineID = .media) throws(JobError) {
        let resolved = tool.resolvingSymlinksInPath().standardizedFileURL.path
        let root = policy.bundleRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
            logger.error("Helper outside the app bundle: \(resolved, privacy: .private)")
            throw .engineDamaged(engine)
        }
        if policy.teamID != nil && policy.requirement == nil {
            logger.error("Malformed Team ID; helper not trusted")
            throw .engineDamaged(engine)
        }
        try validate(URL(fileURLWithPath: resolved), requirementText: policy.requirement, engine: engine)
    }

    private static func validate(_ tool: URL, requirementText: String?, engine: EngineID) throws(JobError) {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(tool as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw damaged(status, tool, engine) }
        var requirement: SecRequirement?
        if let requirementText {
            status = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
            guard status == errSecSuccess else { throw damaged(status, tool, engine) }
        }
        status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else { throw damaged(status, tool, engine) }
    }

    private static func damaged(_ status: OSStatus, _ tool: URL, _ engine: EngineID) -> JobError {
        logger.error(
            "Helper signature check failed: OSStatus \(status, privacy: .public) \(tool.path, privacy: .private)")
        return .engineDamaged(engine)
    }
}

/// Checks the media tools before their first use; injected so engine tests can run with scripted tools.
public protocol HelperIntegrityChecking: Sendable {
    func check(_ tools: MediaTools) throws(JobError)
}

/// The production check: bundled tools must pass `HelperIntegrity`; `override` and `development` tools, which only
/// Debug builds use, are not checked.
public struct SignedHelperCheck: HelperIntegrityChecking {
    private let policy: Policy?
    public typealias Policy = HelperIntegrity.Policy

    /// `policy` nil means the running app's policy, read when the check runs.
    public init(policy: Policy? = nil) {
        self.policy = policy
    }

    public func check(_ tools: MediaTools) throws(JobError) {
        guard tools.origin == .bundled else { return }
        let policy = policy ?? .current()
        try HelperIntegrity.check(tools.ffmpeg, policy: policy)
        try HelperIntegrity.check(tools.ffprobe, policy: policy)
    }
}
