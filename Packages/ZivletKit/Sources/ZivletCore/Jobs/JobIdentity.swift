import Foundation

/// One job: one input converted to one output (02 §7.2).
public struct JobID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UUID

    public init(_ raw: UUID = UUID()) { self.raw = raw }

    public var description: String { raw.uuidString.lowercased() }
}

/// The jobs submitted by one drop or one call; the HUD shows one batch.
public struct BatchID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UUID

    public init(_ raw: UUID = UUID()) { self.raw = raw }

    public var description: String { raw.uuidString.lowercased() }
}

/// The engine that runs a plan (02 §7.3). M3 ships the ffmpeg media engine and the ImageIO image engine.
public enum EngineID: String, CaseIterable, Codable, Sendable {
    case media, image
}
