/// One bundled helper or library and its version, for Settings › Advanced (03b §8.1). `version == nil` means the
/// helper was not found, failed its signature check, or did not answer.
public struct HelperVersion: Sendable, Equatable {
    public let name: String
    public let version: String?

    public init(name: String, version: String?) {
        self.name = name
        self.version = version
    }
}

/// An engine that can say which helper versions it runs.
public protocol HelperVersionReporting: Sendable {
    func helperVersions() async -> [HelperVersion]
}
