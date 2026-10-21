import CWebP
import Foundation
import ZivletCore

/// Adds `ICCP`, `EXIF` and `XMP ` chunks to an encoded WebP with libwebp's mux API (the `VP8X` header is written by
/// the muxer). Returns the input unchanged when there is nothing to add.
enum WebPMuxer {
    static let failure = "The WebP metadata could not be added."

    static func assemble(_ encoded: Data, icc: Data?, exif: Data?, xmp: Data?) throws(JobError) -> Data {
        let chunks = [("ICCP", icc), ("EXIF", exif), ("XMP ", xmp)].compactMap { name, data in
            data.flatMap { $0.isEmpty ? nil : (name, $0) }
        }
        guard !chunks.isEmpty else { return encoded }
        let mux = encoded.withUnsafeBytes { raw -> OpaquePointer? in
            var input = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
            return WebPMuxCreate(&input, 1)
        }
        guard let mux else { throw .writeFailed(failure) }
        defer { WebPMuxDelete(mux) }
        for (name, data) in chunks {
            let status = data.withUnsafeBytes { raw -> WebPMuxError in
                var chunk = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
                return WebPMuxSetChunk(mux, name, &chunk, 1)
            }
            guard status == WEBP_MUX_OK else { throw .writeFailed(failure) }
        }
        var output = WebPData()
        defer { WebPDataClear(&output) }
        guard WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let bytes = output.bytes else {
            throw .writeFailed(failure)
        }
        return Data(bytes: bytes, count: output.size)
    }
}
