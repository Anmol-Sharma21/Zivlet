import ZivletCore
import os

/// Text recognition group (P2-103, D-M6-14), stored as `settings.text.v1`: the language choice and what the one-time
/// warm-up was last done for. It holds a choice, an OS build and language identifiers only, never recognised text
/// (D14). An unknown stored choice reads as the default (with one log line) and keeps the rest of the group.
public struct TextGroup: Sendable, Equatable {
    public var language = TextLanguageChoice.matchMine
    public var warmed: TextWarmupRecord?

    public init() {}
}

extension TextGroup: Codable {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "settings")

    private enum CodingKeys: String, CodingKey { case language, warmed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        warmed = try container.decodeIfPresent(TextWarmupRecord.self, forKey: .warmed)
        guard let raw = try container.decodeIfPresent(String.self, forKey: .language) else { return }
        guard let choice = TextLanguageChoice(rawValue: raw) else {
            Self.logger.error("Unknown text recognition choice; using Match my languages")
            return
        }
        language = choice
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language.rawValue, forKey: .language)
        try container.encodeIfPresent(warmed, forKey: .warmed)
    }
}
