import AVFoundation
import Foundation
import ZivletCore

/// Whether macOS can play a finished MP4 or MOV (03b §5.9). A protocol so engine tests can answer without
/// AVFoundation reading fake files.
public protocol PlayabilityChecking: Sendable {
    func isPlayable(_ url: URL, as format: FormatID) async -> Bool
}

/// `AVURLAsset.load(.isPlayable)`. The staged file's name has no meaningful extension, so the MIME type is given.
public struct AVPlayability: PlayabilityChecking {
    static let mimeTypes: [FormatID: String] = [.mp4: "video/mp4", .mov: "video/quicktime"]

    public init() {}

    public func isPlayable(_ url: URL, as format: FormatID) async -> Bool {
        let options = Self.mimeTypes[format].map { [AVURLAssetOverrideMIMETypeKey: $0] } ?? [:]
        return (try? await AVURLAsset(url: url, options: options).load(.isPlayable)) ?? false
    }
}
