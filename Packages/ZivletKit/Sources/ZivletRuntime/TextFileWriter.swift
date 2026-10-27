import Foundation
import ZivletCore
import ZivletEngineKit

/// "Save as Text" and ⌥ Copy Text (P2-104): writes `<name> Text.txt` beside the input, or in the fallback folder when
/// the input's folder is read-only (01-prd FR-17). UTF-8 without a byte-order mark, LF line breaks. The text goes to
/// a private staging file first and is published with the exclusive rename, so nothing is ever replaced; the input's
/// quarantine is copied like any other output's (10 §8.5).
public struct TextFileWriter: Sendable {
    let publisher: Publisher
    let namer: OutputNamer
    let fallbackFolder: URL

    public init(
        fallbackFolder: URL = URL.downloadsDirectory, publisher: Publisher = Publisher(),
        namer: OutputNamer = OutputNamer()
    ) {
        self.fallbackFolder = fallbackFolder
        self.publisher = publisher
        self.namer = namer
    }

    public func write(_ text: String, beside input: URL) throws(JobError) -> URL {
        let folder = input.deletingLastPathComponent()
        let destination = JobRequestFactory.isWritableFolder(folder) ? folder : fallbackFolder
        let staged = try StagingDirectory.claim(in: destination, job: JobID(), ext: "txt")
        do throws(JobError) {
            let bytes = Data(Self.lineFeeds(text).utf8)
            try Self.fill(staged, with: bytes)
            guard let name = namer.tool(.copyText, source: input.lastPathComponent, format: .txt) else {
                throw .internalInvariant("Copy Text has no output name.")
            }
            let output = StagedOutput(format: .txt, url: staged, byteCount: Int64(bytes.count))
            return try publisher.publish(
                output, as: name, in: destination, quarantine: Publisher.quarantine(of: input)
            ).url
        } catch {
            try? StagingDirectory.remove(staged)
            throw error
        }
    }

    /// CRLF and CR become LF.
    static func lineFeeds(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Writes into the empty staged file the claim created (never through a symlink).
    static func fill(_ staged: URL, with bytes: Data) throws(JobError) {
        do {
            let handle = try FileHandle(forWritingTo: staged)
            defer { try? handle.close() }
            try handle.write(contentsOf: bytes)
        } catch {
            throw .writeFailed("The text file could not be written.")
        }
    }
}
