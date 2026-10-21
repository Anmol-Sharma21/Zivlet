import CWebP
import CoreGraphics
import Foundation
import ZivletCore
import ZivletEngineKit

/// Encodes frames with libwebp in-process (P1-25, D-M4-8): `WebPEncode` for a still, `WebPAnimEncoder` for an
/// animation, then `WebPMuxer` adds the ICC profile, EXIF and XMP. Frames arrive upright (orientation baked, written
/// as 1, D-M3-29) from `frame`, are drawn into 8-bit RGBA at the canvas size and handed over with straight alpha.
/// `cancel` is polled before every frame; every libwebp object is freed on every path. Callers run it through
/// `BlockingWork` (D-M3-10).
enum WebPWriter {
    /// What the writer needs besides the pixels.
    struct Job {
        let count: Int
        let canvas: PixelSize
        let timing: AnimationTiming
        let metadata: WebPMetadata
        let options: WebPOptions
        /// `convertToSRGB` draws every frame in sRGB and embeds no profile (untagged WebP is sRGB).
        var colour: ImageColour = .keep

        func space(for image: CGImage) -> CGColorSpace {
            colour == .convertToSRGB ? RGBAFrame.srgb : RGBAFrame.space(for: image)
        }
    }

    static func write(
        _ job: Job, to staged: URL, cancel: CancellationFlag, frame: (Int) throws(JobError) -> CGImage
    ) throws(JobError) {
        var config = try config(job.options)
        let animated = job.options.animated && job.count > 1
        let (encoded, space) =
            animated
            ? try animate(job, config: &config, cancel: cancel, frame: frame)
            : try still(job, config: &config, cancel: cancel, frame: frame)
        let icc = job.metadata.keepsProfile && job.colour == .keep ? space.copyICCData() as Data? : nil
        let bytes = try WebPMuxer.assemble(encoded, icc: icc, exif: job.metadata.exif, xmp: job.metadata.xmp)
        try StagedBytes.write(bytes, to: staged)
    }

    static func config(_ options: WebPOptions) throws(JobError) -> WebPConfig {
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw .internalInvariant("libwebp refused its own defaults") }
        config.quality = Float(options.quality)
        config.method = Int32(options.method)
        config.use_sharp_yuv = options.sharpYUV ? 1 : 0
        config.exact = options.exactAlpha ? 1 : 0
        config.lossless = options.lossless ? 1 : 0
        guard WebPValidateConfig(&config) != 0 else { throw .internalInvariant("libwebp refused the WebP settings") }
        return config
    }

    private static func still(
        _ job: Job, config: inout WebPConfig, cancel: CancellationFlag, frame: (Int) throws(JobError) -> CGImage
    ) throws(JobError) -> (Data, CGColorSpace) {
        if cancel.isCancelled { throw .cancelled }
        let image = try frame(0)
        let space = job.space(for: image)
        let pixels = try RGBAFrame(image, canvas: job.canvas, space: space, alpha: job.options.exactAlpha)
        let data = try pixels.withPicture { (picture: inout WebPPicture) throws(JobError) -> Data in
            try encode(&picture, config: &config)
        }
        return (data, space)
    }

    private static func encode(_ picture: inout WebPPicture, config: inout WebPConfig) throws(JobError) -> Data {
        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let ok = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard ok != 0, let memory = writer.mem else { throw WebPEncodeFailure.error(picture.error_code) }
        return Data(bytes: memory, count: writer.size)
    }

    private static func animate(
        _ job: Job, config: inout WebPConfig, cancel: CancellationFlag, frame: (Int) throws(JobError) -> CGImage
    ) throws(JobError) -> (Data, CGColorSpace) {
        var options = WebPAnimEncoderOptions()
        guard WebPAnimEncoderOptionsInit(&options) != 0 else { throw .internalInvariant("libwebp animation defaults") }
        options.anim_params.loop_count = Int32(job.timing.loopCount)
        let (width, height) = (Int32(job.canvas.width), Int32(job.canvas.height))
        guard let encoder = WebPAnimEncoderNew(width, height, &options) else {
            throw .writeFailed(WebPEncodeFailure.outOfMemory)
        }
        defer { WebPAnimEncoderDelete(encoder) }
        var space: CGColorSpace?
        var timestamp: Int32 = 0
        for position in 0..<job.count {
            if cancel.isCancelled { throw .cancelled }
            let image = try frame(position)
            let frameSpace = space ?? job.space(for: image)
            space = frameSpace
            let pixels = try RGBAFrame(image, canvas: job.canvas, space: frameSpace, alpha: job.options.exactAlpha)
            try pixels.withPicture { (picture: inout WebPPicture) throws(JobError) in
                guard WebPAnimEncoderAdd(encoder, &picture, timestamp, &config) != 0 else {
                    throw WebPEncodeFailure.error(picture.error_code)
                }
            }
            timestamp += Int32(job.timing.duration(at: position))
        }
        return (try assemble(encoder, end: timestamp), space ?? RGBAFrame.srgb)
    }

    private static func assemble(_ encoder: OpaquePointer, end: Int32) throws(JobError) -> Data {
        var data = WebPData()
        defer { WebPDataClear(&data) }
        guard WebPAnimEncoderAdd(encoder, nil, end, nil) != 0, WebPAnimEncoderAssemble(encoder, &data) != 0,
            let bytes = data.bytes
        else { throw .writeFailed(WebPEncodeFailure.animation) }
        return Data(bytes: bytes, count: data.size)
    }
}

/// libwebp encoder errors as Zivlet errors.
enum WebPEncodeFailure {
    static let outOfMemory = "The WebP encoder ran out of memory."
    static let animation = "The WebP animation could not be assembled."

    static func error(_ code: WebPEncodingError) -> JobError {
        switch code {
        case VP8_ENC_ERROR_OUT_OF_MEMORY, VP8_ENC_ERROR_BITSTREAM_OUT_OF_MEMORY: .writeFailed(outOfMemory)
        case VP8_ENC_ERROR_BAD_DIMENSION: .unsupportedInput(.tooLarge)
        case VP8_ENC_ERROR_USER_ABORT: .cancelled
        default: .writeFailed("The WebP encoder stopped with error \(code.rawValue).")
        }
    }
}
