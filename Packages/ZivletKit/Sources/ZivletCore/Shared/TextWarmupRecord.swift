/// What text recognition was last warmed for (P2-103): the OS build and the ordered language identifiers
/// (`hi-Deva`, `en-Latn`). Stored by the settings, compared by `WarmupState`.
public struct TextWarmupRecord: Codable, Sendable, Equatable {
    public let osBuild: String
    public let languages: [String]

    public init(osBuild: String, languages: [String]) {
        self.osBuild = osBuild
        self.languages = languages
    }
}
