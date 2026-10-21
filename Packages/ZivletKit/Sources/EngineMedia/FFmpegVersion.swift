import Foundation
import ZivletEngineKit

/// `ffmpeg -version`'s first line is "ffmpeg version <v> Copyright …"; `<v>` is what Settings shows.
enum FFmpegVersion {
    static let prefix = "ffmpeg version "

    static func parse(_ output: String) -> String? {
        guard let first = output.split(separator: "\n").first, first.hasPrefix(prefix) else { return nil }
        return first.dropFirst(prefix.count).split(separator: " ").first.map(String.init)
    }
}

extension MediaEngine: HelperVersionReporting {
    /// Locates ffmpeg and checks its signature exactly as a conversion would, then asks it.
    public func helperVersions() async -> [HelperVersion] {
        [HelperVersion(name: "FFmpeg", version: await ffmpegVersion())]
    }

    private func ffmpegVersion() async -> String? {
        let tools: MediaTools
        do {
            tools = try toolbox.locateChecked()
        } catch {
            return nil
        }
        let request = SubprocessRequest(executable: tools.ffmpeg, arguments: ["-hide_banner", "-version"])
        guard let result = try? await runner.run(request, onSpawn: { _ in }, onLine: { _ in }),
            result.termination == .exited(0)
        else { return nil }
        return FFmpegVersion.parse(String(decoding: result.stdout, as: UTF8.self))
    }
}
