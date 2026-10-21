/// Scheduler lanes (02 §7.3, 03a §4.2). Plans name the lane; the runtime (P1) owns the widths.
public enum Lane: String, CaseIterable, Codable, Sendable {
    case cpu, remux, audio, hwVideo, swVideo, render, js, vision, metadata, office, iwork
}
