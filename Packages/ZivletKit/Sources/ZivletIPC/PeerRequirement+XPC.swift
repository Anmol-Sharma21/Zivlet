@preconcurrency import XPC

extension PeerRequirementSpec {
    /// The XPC requirement for this spec (prototype: `isFromSameTeam` refuses ad-hoc code, a lightweight code
    /// requirement on the signing identifier accepts it and refuses another identifier).
    public var xpcRequirement: XPCPeerRequirement {
        switch self {
        case .sameTeam(let identifier): return .isFromSameTeam(andMatchesSigningIdentifier: identifier)
        case .signingIdentifier(let identifier):
            var requirements = XPCDictionary()
            requirements["signing-identifier"] = identifier
            return XPCPeerRequirement(lightweightCodeRequirements: requirements)
        }
    }
}
