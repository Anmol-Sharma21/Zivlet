import Darwin
import Foundation
import ZivletCore

/// A dropped item that never became a job, with the reason.
public struct RequestRejection: Sendable, Equatable {
    public let url: URL
    public let error: JobError

    public init(url: URL, error: JobError) {
        self.url = url
        self.error = error
    }
}

public struct RequestPlan: Sendable, Equatable {
    public let requests: [JobRequest]
    public let rejections: [RequestRejection]

    public init(requests: [JobRequest], rejections: [RequestRejection]) {
        self.requests = requests
        self.rejections = rejections
    }
}

/// Dropped URLs → validated job requests (P1-33, 03a §4.3 location rule). The boundary check for drops: each URL
/// must be a regular local file (not a symlink, FIFO or folder) with a known extension, a catalog pair to `target`
/// and content that agrees (03a §3.2). Outputs go beside the
/// original, or into `fallbackFolder` (Downloads) when that folder is not writable (01-prd FR-17).
public struct JobRequestFactory: Sendable {
    let fallbackFolder: URL
    let registry: FormatRegistry
    let catalog: ConversionCatalog

    public init(
        fallbackFolder: URL = URL.downloadsDirectory, registry: FormatRegistry = .standard,
        catalog: ConversionCatalog = .standard
    ) {
        self.fallbackFolder = fallbackFolder
        self.registry = registry
        self.catalog = catalog
    }

    /// A copy that sends read-only-folder outputs to `fallbackFolder`.
    public func with(fallbackFolder: URL) -> JobRequestFactory {
        JobRequestFactory(fallbackFolder: fallbackFolder, registry: registry, catalog: catalog)
    }

    public func requests(for urls: [URL], target: FormatID) -> RequestPlan {
        var requests: [JobRequest] = []
        var rejections: [RequestRejection] = []
        for url in urls {
            switch request(for: url, target: target) {
            case .success(let request): requests.append(request)
            case .failure(let error): rejections.append(RequestRejection(url: url, error: error))
            }
        }
        return RequestPlan(requests: requests, rejections: rejections)
    }

    /// Regular file → known extension → catalog pair → content (the sniffed type wins, G-8) → request.
    private func request(for url: URL, target: FormatID) -> Result<JobRequest, JobError> {
        Result { () throws(JobError) -> JobRequest in
            let header = try InputHeader.read(url)
            guard let named = registry.formatID(fileName: url.lastPathComponent) else {
                throw .unsupportedInput(.unknownFormat)
            }
            guard catalog.canConvert(named, to: target) else { throw .pairNotSupported(named, target) }
            let verdict = try ContentAdmission.resolve(
                named: named, header: header.bytes, target: target, catalog: catalog)
            let input = try InputItem(
                url: url, format: verdict.format, byteCount: header.byteCount,
                quarantine: Publisher.quarantine(of: url), namedFormat: verdict.isSniffed ? named : nil)
            return try JobRequest(
                input: input, operation: .convert(target), destination: destination(for: url), catalog: catalog)
        }
    }

    private func destination(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        return access(folder.path, W_OK) == 0 ? folder : fallbackFolder
    }

}
