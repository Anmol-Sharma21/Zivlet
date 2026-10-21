import Darwin
import Foundation
import ZivletCore
import zlib

/// The bytes of an SVG or SVGZ source, within the input caps (03b §6.4): at most 64 MiB on disk and, once
/// gunzipped, at most 64 MiB and at most 100 times the compressed size, so a gzip bomb is refused while it inflates.
/// A file that starts with the gzip magic is gunzipped whatever its extension.
enum SVGSource {
    static let maxBytes = 64 << 20
    static let maxRatio = 100
    static let gzipMagic: [UInt8] = [0x1F, 0x8B]

    static func read(_ url: URL) throws(JobError) -> Data {
        let raw = try readCapped(url)
        guard raw.starts(with: gzipMagic) else { return raw }
        let ratioCap = raw.count.multipliedReportingOverflow(by: maxRatio)
        return try Gunzip.decompress(raw, limit: ratioCap.overflow ? maxBytes : min(maxBytes, ratioCap.partialValue))
    }

    /// A regular file's bytes; refused from its size before anything is read.
    static func readCapped(_ url: URL) throws(JobError) -> Data {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw .unsupportedInput(.unreadable) }
        guard info.st_size <= maxBytes else { throw .unsupportedInput(.tooLarge) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw .unsupportedInput(.unreadable) }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            throw .unsupportedInput(.unreadable)
        }
        guard data.count <= maxBytes else { throw .unsupportedInput(.tooLarge) }
        return data
    }
}

/// gzip decompression with zlib, stopping as soon as the output passes `limit`.
enum Gunzip {
    static let chunk = 64 << 10
    /// zlib window bits for gzip framing only.
    static let gzipWindowBits: Int32 = 31

    private enum Outcome { case done, tooLarge, corrupt }

    static func decompress(_ data: Data, limit: Int) throws(JobError) -> Data {
        var stream = z_stream()
        let started = inflateInit2_(&stream, gzipWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard started == Z_OK else { throw .internalInvariant("zlib could not start") }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        let outcome = data.withUnsafeBytes { input -> Outcome in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            while true {
                let status = buffer.withUnsafeMutableBytes { out -> Int32 in
                    stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunk)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunk - Int(stream.avail_out)
                guard output.count + produced <= limit else { return .tooLarge }
                output.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END { return .done }
                if status != Z_OK { return .corrupt }
            }
        }
        switch outcome {
        case .done: return output
        case .tooLarge: throw .unsupportedInput(.tooLarge)
        case .corrupt: throw .unsupportedInput(.unreadable)
        }
    }
}
