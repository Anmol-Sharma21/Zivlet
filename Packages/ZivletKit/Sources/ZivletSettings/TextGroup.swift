import ZivletCore

/// Text recognition group (P2-103), stored as `settings.text.v1`: what the one-time warm-up was last done for. It
/// holds an OS build and language identifiers only, never recognised text (D14).
public struct TextGroup: Sendable, Equatable, Codable {
    public var warmed: TextWarmupRecord?

    public init() {}
}
