import EngineVision
import Foundation
import ZivletCore

/// One Read QR job for the worker (P2-51, plan 20b A8): the dropped files by absolute path (D-M6-4) and the page
/// limit for each PDF. Its progress travels as `WorkerEvent.progress` under `id`; `cancel(id)` stops it.
public struct CodeJob: Codable, Sendable, Equatable {
    /// More files than this in one drop are refused at the boundary.
    public static let maximumInputs = 500

    public let id: JobID
    public let inputs: [URL]
    public let pageLimit: Int

    public init(id: JobID = JobID(), inputs: [URL], pageLimit: Int = PDFTextSource.pageLimit) {
        self.id = id
        self.inputs = inputs
        self.pageLimit = pageLimit
    }
}

/// One file's answer: its name and codes, or the error that kept it from being read (the others are still read).
public struct FileCodes: Codable, Sendable, Equatable {
    public let name: String
    public let codes: [FoundCode]
    public let error: CodeError?

    public init(name: String, codes: [FoundCode]) {
        self.name = name
        self.codes = codes
        error = nil
    }

    public init(name: String, error: CodeError) {
        self.name = name
        codes = []
        self.error = error
    }
}
