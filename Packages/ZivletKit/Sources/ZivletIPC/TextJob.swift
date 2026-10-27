import EngineVision
import Foundation
import ZivletCore

/// One Copy Text job for the worker (P2-104, plan 18d D8): the dropped files by absolute path (D-M6-4) and the
/// ordered recognition languages. Its progress travels as `WorkerEvent.progress` under `id`; `cancel(id)` stops it.
public struct TextJob: Codable, Sendable, Equatable {
    /// More files than this in one drop are refused at the boundary.
    public static let maximumInputs = 200
    /// Hindi and English today; room for a few more.
    public static let maximumLanguages = 4

    public let id: JobID
    public let inputs: [URL]
    public let languages: [LanguageTag]

    public init(id: JobID = JobID(), inputs: [URL], languages: [LanguageTag]) {
        self.id = id
        self.inputs = inputs
        self.languages = languages
    }
}
