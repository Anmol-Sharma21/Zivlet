import CWebP
import ZivletEngineKit

extension ImageEngine: HelperVersionReporting {
    /// resvg's C ABI (our zivlet-svg crate) has no version call; this follows the crate's `=` pin, and a test keeps
    /// the two in step.
    public static let resvgVersion = "0.47.0"

    /// libwebp answers for itself; resvg is the pinned number.
    public func helperVersions() async -> [HelperVersion] {
        [
            HelperVersion(name: "libwebp", version: Self.libwebpVersion(WebPGetEncoderVersion())),
            HelperVersion(name: "resvg", version: Self.resvgVersion),
        ]
    }

    /// 0x010600 → "1.6.0".
    static func libwebpVersion(_ packed: Int32) -> String {
        "\((packed >> 16) & 0xFF).\((packed >> 8) & 0xFF).\(packed & 0xFF)"
    }
}
