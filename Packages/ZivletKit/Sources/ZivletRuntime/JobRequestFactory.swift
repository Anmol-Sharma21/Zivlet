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
/// must be a regular local file with a known extension and a catalog pair to `target`. Outputs go beside the
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

    private func request(for url: URL, target: FormatID) -> Result<JobRequest, JobError> {
        Result { () throws(JobError) -> JobRequest in
            let size = try Self.regularFileSize(url)
            guard let format = registry.formatID(fileName: url.lastPathComponent) else {
                throw .unsupportedInput(.unknownFormat)
            }
            let input = try InputItem(
                url: url, format: format, byteCount: size, quarantine: Publisher.quarantine(of: url))
            return try JobRequest(
                input: input, operation: .convert(target), destination: destination(for: url), catalog: catalog)
        }
    }

    private func destination(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        return access(folder.path, W_OK) == 0 ? folder : fallbackFolder
    }

    /// Follows symlinks; only regular files qualify (folders, devices and sockets do not).
    static func regularFileSize(_ url: URL) throws(JobError) -> Int64 {
        var info = stat()
        guard url.isFileURL, stat(url.path, &info) == 0 else { throw .unsupportedInput(.unreadable) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw .unsupportedInput(.notAFile) }
        return Int64(info.st_size)
    }
}
