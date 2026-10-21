/// The three wheels. Lives in Core because both Trigger and WheelCore need it (02 §4 graph).
public enum WheelMode: String, CaseIterable, Codable, Sendable {
    case convert, tools, actions
}
