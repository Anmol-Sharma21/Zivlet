/// Encoder quality ladder step shared by every engine (03b §5.4–5.5, §6.2): small = Compact, standard = Balanced,
/// best = High.
public enum QualityTier: String, CaseIterable, Sendable, Codable {
    case small, standard, best
}
